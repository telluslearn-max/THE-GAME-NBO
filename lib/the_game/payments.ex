defmodule TheGame.Payments do
  @moduledoc """
  Payment rules. The invariants, in order of importance:

    1. A customer is never prompted twice for one order without us knowing the first
       prompt is resolved (cooldown + "unresolved" lock + STK status check).
    2. A repeated or replayed callback changes nothing (receipt uniqueness + row locks).
    3. Money that does not cleanly settle an order is never dropped or guessed at: it
       becomes a `Review` for staff, and the order is flagged.
    4. Callbacks are not trusted blindly: they must match a payment we created, by
       checkout id and amount.
  """
  import Ecto.Query
  alias TheGame.{Mpesa, Orders, Phone, Repo}
  alias TheGame.Orders.Order
  alias TheGame.Payments.{Payment, Review}

  def cooldown_seconds, do: Application.get_env(:the_game, :stk_cooldown_seconds, 60)

  ## Reads

  def latest_payment(order_id) do
    from(p in Payment,
      where: p.order_id == ^order_id,
      order_by: [desc: p.inserted_at, desc: p.id],
      limit: 1
    )
    |> Repo.one()
  end

  def pending_review(order_id) do
    from(r in Review, where: r.order_id == ^order_id and r.status == :pending, limit: 1)
    |> Repo.one()
  end

  def list_reviews(status \\ :pending) do
    from(r in Review,
      where: r.status == ^status,
      order_by: [asc: r.inserted_at],
      preload: [:order]
    )
    |> Repo.all()
  end

  ## Requesting a payment

  @type request_error ::
          :not_found
          | :not_payable
          | :already_paid
          | :unresolved
          | {:cooldown, pos_integer}
          | :gateway

  @spec request_stk(String.t()) :: {:ok, Payment.t()} | {:error, request_error}
  def request_stk(order_id) do
    reserved =
      Repo.transaction(fn ->
        order = from(o in Order, where: o.id == ^order_id, lock: "FOR UPDATE") |> Repo.one()

        with %Order{} <- order || {:error, :not_found},
             :ok <- payable(order),
             :ok <- gate(latest_payment(order.id)) do
          Repo.insert!(%Payment{
            order_id: order.id,
            phone: order.payer_phone,
            amount_cents: order.total_cents,
            status: :queued
          })
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    with {:ok, payment} <- reserved, do: push(payment, order_id)
  end

  defp payable(%Order{status: :pending_payment, expires_at: exp}) do
    if DateTime.compare(exp, DateTime.utc_now()) == :gt, do: :ok, else: {:error, :not_payable}
  end

  defp payable(%Order{status: s}) when s in [:paid, :preparing, :ready, :completed],
    do: {:error, :already_paid}

  defp payable(_), do: {:error, :not_payable}

  defp gate(nil), do: :ok
  defp gate(%Payment{status: :success}), do: {:error, :already_paid}

  defp gate(%Payment{status: s} = p) when s in [:queued, :sent] do
    age = DateTime.diff(DateTime.utc_now(), p.inserted_at)
    cd = cooldown_seconds()
    if age < cd, do: {:error, {:cooldown, cd - age}}, else: {:error, :unresolved}
  end

  defp gate(%Payment{}), do: :ok

  defp push(%Payment{} = payment, order_id) do
    order = Orders.get_order!(order_id)

    req = %{
      phone: payment.phone,
      amount: div(payment.amount_cents, 100),
      reference: order.pickup_code,
      description: "THE GAME"
    }

    case safe(fn -> Mpesa.stk_push(req) end) do
      {:ok, %{checkout_request_id: cid, merchant_request_id: mid}} ->
        payment
        |> Ecto.Changeset.change(%{
          status: :sent,
          checkout_request_id: cid,
          merchant_request_id: mid,
          sent_at: now()
        })
        |> Repo.update()
        |> tap(fn _ -> Orders.notify(order) end)

      {:error, reason} ->
        payment
        |> Ecto.Changeset.change(%{
          status: :failed,
          result_desc: inspect(reason) |> String.slice(0, 200)
        })
        |> Repo.update!()

        Orders.notify(order)
        {:error, :gateway}
    end
  end

  # A crashing/timing-out gateway must never take the request process down mid-payment.
  defp safe(fun) do
    fun.()
  rescue
    e -> {:error, {:exception, Exception.message(e)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  ## Resolving an unresolved prompt

  @doc "Ask Safaricom what happened to the latest prompt. Safe to call repeatedly."
  @spec check(String.t()) :: {:ok, :none | :pending | :paid | :failed} | {:error, term}
  def check(order_id) do
    case latest_payment(order_id) do
      %Payment{status: :sent, checkout_request_id: cid} when is_binary(cid) ->
        case safe(fn -> Mpesa.stk_query(cid) end) do
          {:ok, %{status: :pending}} ->
            {:ok, :pending}

          {:ok, %{status: status, code: code, desc: desc, receipt: receipt}} ->
            settle(cid, %{
              status: status,
              code: code,
              desc: desc,
              receipt: receipt,
              amount: nil,
              source: :query
            })
            |> case do
              {:ok, :paid} -> {:ok, :paid}
              {:ok, _} -> {:ok, :failed}
              {:error, e} -> {:error, e}
            end

          {:error, e} ->
            {:error, e}
        end

      %Payment{status: :success} ->
        {:ok, :paid}

      %Payment{status: s} when s in [:failed, :cancelled, :timeout] ->
        {:ok, :failed}

      _ ->
        {:ok, :none}
    end
  end

  ## Reconciliation

  @doc """
  Query prompts that have been waiting for a result longer than `min_age` seconds (but not
  forever) for orders that can still be affected. Returns how many were resolved.
  """
  def reconcile(min_age \\ 45, max_age \\ 3 * 3600) do
    now = DateTime.utc_now()
    newest = DateTime.add(now, -min_age)
    oldest = DateTime.add(now, -max_age)

    from(p in Payment,
      where: p.status == :sent and p.inserted_at <= ^newest and p.inserted_at >= ^oldest,
      order_by: p.inserted_at,
      limit: 10,
      select: p.order_id
    )
    |> Repo.all()
    |> Enum.count(fn order_id -> match?({:ok, r} when r in [:paid, :failed], check(order_id)) end)
  end

  ## Callback

  @doc "Handle a Daraja STK callback body. Always safe to replay."
  def handle_callback(%{"Body" => %{"stkCallback" => cb}}) when is_map(cb) do
    code = cb["ResultCode"]
    items = get_in(cb, ["CallbackMetadata", "Item"]) || []
    meta = Map.new(items, fn i -> {i["Name"], i["Value"]} end)

    settle(cb["CheckoutRequestID"], %{
      status: Mpesa.classify(code),
      code: code,
      desc: cb["ResultDesc"],
      receipt: meta["MpesaReceiptNumber"],
      amount: meta["Amount"],
      source: :callback
    })
  end

  def handle_callback(_), do: {:error, :malformed}

  # Shared by callbacks and STK queries so both take exactly the same path.
  defp settle(checkout_id, result) when is_binary(checkout_id) do
    tx =
      Repo.transaction(fn ->
        payment =
          from(p in Payment, where: p.checkout_request_id == ^checkout_id, lock: "FOR UPDATE")
          |> Repo.one()

        cond do
          is_nil(payment) ->
            Repo.rollback(:unknown_payment)

          payment.status == :success ->
            {:noop, nil}

          payment.status in [:failed, :cancelled, :timeout] and result.status != :success ->
            {:noop, nil}

          result.status == :success ->
            settle_success(payment, result)

          true ->
            settle_failure(payment, result)
        end
      end)

    case tx do
      {:ok, {:noop, _}} ->
        {:ok, :noop}

      {:ok, {outcome, order}} ->
        if order, do: Orders.notify(Orders.get_order!(order.id))
        {:ok, outcome}

      {:error, e} ->
        {:error, e}
    end
  end

  defp settle_failure(payment, result) do
    payment
    |> Ecto.Changeset.change(%{
      status: result.status,
      result_code: result.code,
      result_desc: String.slice(to_string(result.desc), 0, 200)
    })
    |> Repo.update!()

    {:failed, Repo.get(Order, payment.order_id)}
  end

  defp settle_success(payment, %{receipt: receipt} = result) when is_binary(receipt) do
    # Replay of a receipt we already hold (callback + query racing, or Safaricom retrying).
    if Repo.exists?(from p in Payment, where: p.mpesa_receipt == ^receipt and p.id != ^payment.id) do
      {:noop, nil}
    else
      paid_cents = if result.amount, do: round(result.amount * 100), else: payment.amount_cents

      payment
      |> Ecto.Changeset.change(%{
        status: :success,
        result_code: 0,
        result_desc: "ok",
        mpesa_receipt: receipt
      })
      |> Repo.update!()

      apply_to_order(payment, receipt, paid_cents)
    end
  end

  # Success without a receipt cannot be reconciled; treat as unresolved money for staff.
  defp settle_success(payment, _result) do
    payment |> Ecto.Changeset.change(%{status: :success, result_code: 0}) |> Repo.update!()
    order = Repo.get(Order, payment.order_id)

    review!(
      order,
      :unmatched,
      "NO-RECEIPT-#{payment.id}",
      payment,
      payment.amount_cents,
      "Success reported without a receipt number"
    )

    {:review, order}
  end

  defp apply_to_order(payment, receipt, paid_cents) do
    order = from(o in Order, where: o.id == ^payment.order_id, lock: "FOR UPDATE") |> Repo.one()

    cond do
      order.status == :pending_payment and paid_cents >= order.total_cents ->
        {:ok, _} = Orders.transition_tx(order.id, :paid, %{mpesa_receipt: receipt})

        if paid_cents > order.total_cents do
          review!(
            order,
            :extra,
            receipt,
            payment,
            paid_cents,
            "Overpaid by #{paid_cents - order.total_cents} cents; refund the difference"
          )
        end

        {:paid, order}

      order.status == :pending_payment ->
        {:ok, _} = Orders.transition_tx(order.id, :flagged)

        review!(
          order,
          :short,
          receipt,
          payment,
          paid_cents,
          "Paid #{paid_cents} of #{order.total_cents} cents"
        )

        {:review, order}

      order.status in [:expired, :cancelled] ->
        {:ok, _} = Orders.transition_tx(order.id, :flagged)

        review!(
          order,
          :late,
          receipt,
          payment,
          paid_cents,
          "Payment arrived after the order was #{order.status}"
        )

        {:review, order}

      true ->
        review!(
          order,
          :extra,
          receipt,
          payment,
          paid_cents,
          "Second payment for an order already #{order.status}; refund"
        )

        {:review, order}
    end
  end

  defp review!(order, kind, receipt, payment, cents, note) do
    Repo.insert!(
      %Review{
        order_id: order.id,
        kind: kind,
        mpesa_receipt: receipt,
        phone: payment.phone,
        amount_cents: cents,
        note: note
      },
      on_conflict: :nothing,
      conflict_target: :mpesa_receipt
    )
  end

  ## Staff resolution of reviews

  @doc """
  `:refunded` / `:closed` end the order (`flagged -> closed`, stock released). `:honored` accepts
  the payment and sends a flagged order to the bar (`flagged -> preparing`).
  """
  def resolve_review(review_id, resolution) when resolution in [:refunded, :closed, :honored] do
    Repo.transaction(fn ->
      review = from(r in Review, where: r.id == ^review_id, lock: "FOR UPDATE") |> Repo.one()

      cond do
        is_nil(review) -> Repo.rollback(:not_found)
        review.status != :pending -> Repo.rollback(:already_resolved)
        true -> :ok
      end

      order_result =
        case {review.order_id && Repo.get(Order, review.order_id), resolution} do
          {%Order{status: :flagged} = o, :honored} ->
            Orders.transition_tx(o.id, :preparing, %{mpesa_receipt: review.mpesa_receipt})

          {%Order{status: :flagged} = o, _} ->
            Orders.transition_tx(o.id, :closed)

          _ ->
            {:ok, nil}
        end

      case order_result do
        {:ok, order} ->
          review
          |> Ecto.Changeset.change(%{status: resolution})
          |> Repo.update!()
          |> then(&{&1, order})

        {:error, e} ->
          Repo.rollback(e)
      end
    end)
    |> tap(fn
      {:ok, {_, %Order{} = o}} -> Orders.notify(o)
      _ -> :ok
    end)
    |> case do
      {:ok, {review, _}} -> {:ok, review}
      other -> other
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  # keep Phone referenced for callers building requests from raw input
  def normalize_phone(p), do: Phone.normalize(p)
end
