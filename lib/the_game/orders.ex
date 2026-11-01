defmodule TheGame.Orders do
  @moduledoc """
  Order lifecycle. All stock and status changes happen inside one DB transaction with
  row locks, so concurrent customers can never oversell and a status can never move
  along an edge the state machine forbids.
  """
  import Ecto.Query
  alias TheGame.{Phone, Repo, Settings}
  alias TheGame.Catalog.Product
  alias TheGame.Orders.{Item, Order, Status}

  @max_units 15
  @code_alphabet ~c"23456789ABCDEFGHJKMNPQRSTUVWXYZ"

  def max_units, do: @max_units
  def ttl_seconds, do: Application.get_env(:the_game, :order_ttl_seconds, 600)

  ## Reads

  def get_order(id) do
    with {:ok, _} <- Ecto.UUID.cast(id) do
      Order |> Repo.get(id) |> Repo.preload([:items, :payments])
    else
      _ -> nil
    end
  end

  def get_order!(id), do: get_order(id) || raise(Ecto.NoResultsError, queryable: Order)

  def list_by_ids(ids) when is_list(ids) do
    ids = ids |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1))) |> Enum.take(30)

    from(o in Order, where: o.id in ^ids, order_by: [desc: o.inserted_at], preload: [:items])
    |> Repo.all()
  end

  @doc "The unpaid order holding this phone, if any."
  def unpaid_for_phone(phone) do
    from(o in Order, where: o.payer_phone == ^phone and o.status == :pending_payment, limit: 1)
    |> Repo.one()
    |> case do
      nil -> nil
      o -> Repo.preload(o, [:items, :payments])
    end
  end

  @doc "Staff queue: live orders that are paid or being worked on."
  def queue do
    from(o in Order,
      where: o.status in [:paid, :preparing, :ready, :flagged],
      order_by: [asc: o.paid_at, asc: o.inserted_at],
      preload: [:items]
    )
    |> Repo.all()
  end

  @doc "Find orders by pickup code (any status, newest first). Staff recovery tool."
  def find_by_code(code) when is_binary(code) do
    code = code |> String.trim() |> String.upcase()

    from(o in Order,
      where: o.pickup_code == ^code,
      order_by: [desc: o.inserted_at],
      limit: 5,
      preload: [:items]
    )
    |> Repo.all()
  end

  ## Serving: "I've got this one" and "Delivered"

  @serving [:paid, :preparing, :ready]

  @doc """
  A waiter takes an order. She types her name and the last 4 characters of the M-Pesa code,
  read from the client's phone. Those 4 characters must match the payment Safaricom reported
  for this order, so a faked SMS cannot be claimed. First waiter to tap wins; the same name
  again is a no-op; anyone else is told who has it.

  The full code is two halves: the system's pickup code (first 4) + the M-Pesa ending (last 4).
  """
  def claim(order_id, name, last4) when is_binary(name) and is_binary(last4) do
    name = name |> String.trim() |> String.slice(0, 30)
    typed = last4 |> String.replace(~r/\s+/, "") |> String.upcase()

    cond do
      name == "" ->
        {:error, :name_required}

      String.length(typed) != 4 ->
        {:error, :code_required}

      true ->
        Repo.transaction(fn ->
          case lock(order_id) do
            nil ->
              Repo.rollback(:not_found)

            %Order{status: s} when s not in @serving ->
              Repo.rollback({:not_open, s})

            %Order{claimed_by_name: held} = o when is_binary(held) ->
              if String.downcase(held) != String.downcase(name),
                do: Repo.rollback({:claimed, held})

              check_code!(o, typed)
              o

            %Order{} = o ->
              check_code!(o, typed)

              o
              |> Ecto.Changeset.change(claimed_by_name: name, claimed_at: now())
              |> Repo.update!()
          end
        end)
        |> reload_and_notify()
    end
  end

  defp check_code!(%Order{mpesa_receipt: receipt}, typed) do
    unless is_binary(receipt) and String.ends_with?(String.upcase(receipt), typed),
      do: Repo.rollback(:code_mismatch)
  end

  @doc "The last 4 characters of the M-Pesa code (what the waiter types and her slip shows)."
  def receipt_end(%{mpesa_receipt: r}) when is_binary(r),
    do: r |> String.upcase() |> String.slice(-4, 4)

  def receipt_end(_), do: nil

  @doc "Give an order back (the waiter can't serve it after all)."
  def release(order_id) do
    Repo.transaction(fn ->
      case lock(order_id) do
        nil -> Repo.rollback(:not_found)
        o -> o |> Ecto.Changeset.change(claimed_by_name: nil, claimed_at: nil) |> Repo.update!()
      end
    end)
    |> reload_and_notify()
  end

  @doc "The drinks are with the customer. Allowed from any serving state: the bar may not use the app."
  def deliver(order_id), do: transition(order_id, :completed)

  defp reload_and_notify({:ok, %Order{id: id}}) do
    o = get_order!(id)
    notify(o)
    {:ok, o}
  end

  defp reload_and_notify(error), do: error

  @doc "Staff lookup: a pickup code, or the last 4+ characters of an M-Pesa code (last 36 hours)."
  def lookup(term) when is_binary(term) do
    t = term |> String.replace(~r/\s+/, "") |> String.upcase()
    since = DateTime.add(DateTime.utc_now(), -36 * 3600)

    # strip LIKE wildcards first: the *cleaned* term must still be a real 4+ character code,
    # or "%%%%" would match every payment
    safe = String.replace(t, ~r/[%_\\]/, "")

    if String.length(t) < 4 or String.length(safe) < 4 do
      []
    else
      from(o in Order,
        where:
          o.status in ^[:paid, :preparing, :ready, :completed, :flagged] and
            o.inserted_at >= ^since and
            (o.pickup_code == ^t or like(o.mpesa_receipt, ^("%" <> safe))),
        order_by: [desc: o.inserted_at],
        limit: 6,
        preload: [:items]
      )
      |> Repo.all()
    end
  end

  @doc "Totals for the current EAT (UTC+3) calendar day."
  def today_summary(now \\ DateTime.utc_now()) do
    eat = DateTime.add(now, 3 * 3600)
    start_eat = %{eat | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    from_utc = DateTime.add(start_eat, -3 * 3600)

    settled = [:paid, :preparing, :ready, :completed, :flagged]

    totals =
      from(o in Order,
        where: o.paid_at >= ^from_utc and o.status in ^[:paid, :preparing, :ready, :completed],
        select: %{orders: count(o.id), revenue_cents: coalesce(sum(o.total_cents), 0)}
      )
      |> Repo.one()

    by_product =
      from(i in Item,
        join: o in Order,
        on: o.id == i.order_id,
        where: o.paid_at >= ^from_utc and o.status in ^[:paid, :preparing, :ready, :completed],
        group_by: i.name,
        order_by: [desc: sum(i.qty), asc: i.name],
        select: %{name: i.name, qty: sum(i.qty), cents: sum(i.qty * i.unit_price_cents)}
      )
      |> Repo.all()

    open = Repo.aggregate(from(o in Order, where: o.status in ^settled), :count)
    Map.merge(totals, %{by_product: by_product, open: open})
  end

  ## Create

  @type error ::
          :ordering_paused
          | :empty
          | :invalid_phone
          | :too_many_units
          | :invalid_quantity
          | :pending_order
          | {:unavailable, [String.t()]}
          | {:total_mismatch, integer}

  @spec create_order(map) :: {:ok, Order.t()} | {:error, error}
  def create_order(attrs), do: create_order(attrs, 3)

  defp create_order(attrs, retries) do
    case do_create(attrs) do
      {:error, :code_collision} when retries > 0 -> create_order(attrs, retries - 1)
      {:error, :code_collision} -> {:error, :unavailable_try_again}
      other -> other
    end
  end

  defp do_create(attrs) do
    with :ok <- check_open(),
         {:ok, payer} <- Phone.normalize(attrs[:payer_phone] || attrs[:phone]),
         {:ok, items} <- normalize_items(attrs[:items]) do
      Repo.transaction(fn ->
        products = lock_products(Enum.map(items, & &1.product_id))

        with :ok <- check_available(items, products),
             total = total(items, products),
             :ok <- check_total(attrs[:expected_total_cents], total),
             :ok <- reserve(items, products),
             {:ok, order} <- insert_order(payer, total, items, products) do
          order = Repo.preload(order, [:items, :payments])
          order
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> tap(fn
        {:ok, order} -> notify(order)
        _ -> :ok
      end)
    else
      :error -> {:error, :invalid_phone}
      {:error, _} = err -> err
    end
  end

  defp check_open, do: if(Settings.ordering_paused?(), do: {:error, :ordering_paused}, else: :ok)

  defp normalize_items(items) when is_list(items) and items != [] do
    merged =
      Enum.reduce(items, %{}, fn i, acc ->
        id = i[:product_id]
        qty = i[:qty]

        cond do
          not is_binary(id) or match?(:error, Ecto.UUID.cast(id)) ->
            throw({:bad, :invalid_quantity})

          not is_integer(qty) or qty < 1 ->
            throw({:bad, :invalid_quantity})

          true ->
            Map.update(acc, id, qty, &(&1 + qty))
        end
      end)

    cond do
      Enum.sum(Map.values(merged)) > @max_units -> {:error, :too_many_units}
      true -> {:ok, Enum.map(merged, fn {id, q} -> %{product_id: id, qty: q} end)}
    end
  catch
    {:bad, reason} -> {:error, reason}
  end

  defp normalize_items(_), do: {:error, :empty}

  defp lock_products(ids) do
    from(p in Product, where: p.id in ^ids, order_by: p.id, lock: "FOR UPDATE")
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp check_available(items, products) do
    bad =
      for %{product_id: id, qty: q} <- items,
          p = Map.get(products, id),
          not (p.active and (is_nil(p.stock) or p.stock >= q)),
          do: p.name

    missing = for %{product_id: id} <- items, not Map.has_key?(products, id), do: "unknown item"

    case bad ++ missing do
      [] -> :ok
      names -> {:error, {:unavailable, Enum.uniq(names)}}
    end
  end

  defp total(items, products),
    do:
      Enum.reduce(items, 0, fn %{product_id: id, qty: q}, a ->
        a + q * products[id].price_cents
      end)

  defp check_total(nil, _), do: :ok
  defp check_total(expected, total) when expected == total, do: :ok
  defp check_total(_, total), do: {:error, {:total_mismatch, total}}

  defp reserve(items, products) do
    for %{product_id: id, qty: q} <- items, products[id].stock != nil do
      from(p in Product, where: p.id == ^id) |> Repo.update_all(inc: [stock: -q])
    end

    :ok
  end

  defp insert_order(payer, total, items, products) do
    expires =
      DateTime.utc_now() |> DateTime.add(ttl_seconds(), :second) |> DateTime.truncate(:second)

    order =
      %Order{
        phone: payer,
        payer_phone: payer,
        total_cents: total,
        pickup_code: gen_code(),
        expires_at: expires,
        items:
          for %{product_id: id, qty: q} <- items do
            p = products[id]
            %Item{product_id: id, name: p.name, unit_price_cents: p.price_cents, qty: q}
          end
      }
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint(:payer_phone, name: :orders_one_unpaid_per_phone)
      |> Ecto.Changeset.unique_constraint(:pickup_code, name: :orders_live_pickup_code)

    case Repo.insert(order) do
      {:ok, o} ->
        {:ok, o}

      {:error, %{errors: errors}} ->
        cond do
          Keyword.has_key?(errors, :payer_phone) -> {:error, :pending_order}
          Keyword.has_key?(errors, :pickup_code) -> {:error, :code_collision}
          true -> {:error, :invalid}
        end
    end
  end

  defp gen_code, do: for(_ <- 1..4, into: "", do: <<Enum.random(@code_alphabet)>>)

  ## Transitions

  @doc """
  Move an order along the state machine. Locks the row, validates the edge, applies
  side effects (timestamps, stock release), broadcasts. Idempotent callers should use
  the `mark_*` helpers below.
  """
  @spec transition(String.t(), atom, map) ::
          {:ok, Order.t()} | {:error, {:illegal_transition, atom, atom} | :not_found}
  def transition(order_id, to, attrs \\ %{}) do
    Repo.transaction(fn ->
      case transition_tx(order_id, to, attrs) do
        {:ok, order} -> order
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> tap(fn
      {:ok, order} ->
        notify(order)
        if order.status == :ready, do: TheGame.Push.notify_ready(order)

      _ ->
        :ok
    end)
  end

  @doc """
  Same as `transition/3` but for use inside a caller's transaction: no broadcast.
  The caller must call `notify/1` after its transaction commits.
  """
  def transition_tx(order_id, to, attrs \\ %{}) do
    case lock(order_id) do
      nil ->
        {:error, :not_found}

      %Order{status: from} = order ->
        if Status.can?(from, to) do
          if Status.holds_stock?(from) and not Status.holds_stock?(to), do: release_stock(order)
          if not Status.holds_stock?(from) and Status.holds_stock?(to), do: reacquire_stock(order)

          changes =
            side_effects(to)
            |> Map.merge(Map.take(attrs, [:mpesa_receipt]))
            |> Map.put(:status, to)

          {:ok,
           order
           |> Ecto.Changeset.change(changes)
           |> Repo.update!()
           |> Repo.preload([:items, :payments], force: true)}
        else
          {:error, {:illegal_transition, from, to}}
        end
    end
  end

  defp side_effects(:paid), do: %{paid_at: now()}
  defp side_effects(:ready), do: %{ready_at: now()}
  defp side_effects(:completed), do: %{completed_at: now()}
  defp side_effects(_), do: %{}

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp lock(id), do: from(o in Order, where: o.id == ^id, lock: "FOR UPDATE") |> Repo.one()

  defp release_stock(order) do
    items = Repo.all(from i in Item, where: i.order_id == ^order.id)

    for %{product_id: pid, qty: q} when not is_nil(pid) <- items do
      from(p in Product, where: p.id == ^pid and not is_nil(p.stock))
      |> Repo.update_all(inc: [stock: q])
    end

    :ok
  end

  # Best effort when staff honour a late payment: take the stock back if it is still there.
  defp reacquire_stock(order) do
    for %{product_id: pid, qty: q} when not is_nil(pid) <-
          Repo.all(from i in Item, where: i.order_id == ^order.id) do
      from(p in Product,
        where: p.id == ^pid and not is_nil(p.stock),
        update: [set: [stock: fragment("greatest(? - ?, 0)", p.stock, ^q)]]
      )
      |> Repo.update_all([])
    end

    :ok
  end

  @doc "Idempotent: a repeated callback for the same receipt returns the paid order untouched."
  def mark_paid(order_id, receipt) do
    case get_order(order_id) do
      %Order{status: s, mpesa_receipt: ^receipt} = o
      when s != :pending_payment and not is_nil(receipt) ->
        {:ok, o}

      _ ->
        transition(order_id, :paid, %{mpesa_receipt: receipt})
    end
  end

  def cancel(order_id), do: transition(order_id, :cancelled)

  @doc "Expire every unpaid order past its reservation. Returns the number expired."
  def expire_due(now \\ DateTime.utc_now()) do
    ids =
      from(o in Order,
        where: o.status == :pending_payment and o.expires_at <= ^now,
        select: o.id
      )
      |> Repo.all()

    Enum.count(ids, fn id -> match?({:ok, _}, transition(id, :expired)) end)
  end

  ## PubSub

  def subscribe(order_id), do: Phoenix.PubSub.subscribe(TheGame.PubSub, "order:" <> order_id)
  def subscribe_staff, do: Phoenix.PubSub.subscribe(TheGame.PubSub, "staff")

  def notify(%Order{} = o) do
    Phoenix.PubSub.broadcast(TheGame.PubSub, "order:" <> o.id, {:order_updated, o})
    Phoenix.PubSub.broadcast(TheGame.PubSub, "staff", {:order_updated, o})
    Phoenix.PubSub.broadcast(TheGame.PubSub, "menu", :menu_changed)
  end
end
