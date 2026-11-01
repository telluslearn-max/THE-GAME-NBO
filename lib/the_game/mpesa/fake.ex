defmodule TheGame.Mpesa.Fake do
  @moduledoc """
  Safaricom stand-in for dev and tests. It speaks the same payload shapes as Daraja and
  feeds callbacks through the real `Payments.handle_callback/1`, so what you see in dev
  is the production code path. Control it with `complete/3`.
  """
  @behaviour TheGame.Mpesa
  use Agent

  def start_link(_), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  @doc "Make the next `stk_push/1` fail, as if Safaricom or the network were down."
  def fail_next, do: Agent.update(__MODULE__, &Map.put(&1, :fail_next, true))

  @impl true
  def stk_push(%{phone: phone, amount: amount} = p) do
    if Agent.get_and_update(
         __MODULE__,
         &{Map.get(&1, :fail_next, false), Map.delete(&1, :fail_next)}
       ) do
      {:error, :fake_gateway_down}
    else
      do_push(phone, amount, p)
    end
  end

  defp do_push(phone, amount, p) do
    n = System.unique_integer([:positive])
    id = "ws_CO_FAKE_#{n}"

    Agent.update(
      __MODULE__,
      &Map.put(&1, id, %{state: :pending, amount: amount, phone: phone, ref: p.reference})
    )

    maybe_auto(id)
    {:ok, %{checkout_request_id: id, merchant_request_id: "mr_#{n}"}}
  end

  @impl true
  def stk_query(id) do
    case Agent.get(__MODULE__, &Map.get(&1, id)) do
      nil ->
        {:error, :not_found}

      %{state: :pending} ->
        {:ok, %{status: :pending}}

      %{state: {status, code, desc, receipt}} ->
        {:ok, %{status: status, code: code, desc: desc, receipt: receipt}}
    end
  end

  @doc "Settle a pushed request. Returns the Daraja-shaped callback payload it delivered (if `deliver: true`)."
  def complete(id, outcome, opts \\ []) do
    st = Agent.get(__MODULE__, &Map.fetch!(&1, id))
    receipt = Keyword.get(opts, :receipt, "FK#{:erlang.unique_integer([:positive])}")
    amount = Keyword.get(opts, :amount, st.amount)

    {status, code, desc, rcpt} =
      case outcome do
        :success -> {:success, 0, "The service request is processed successfully.", receipt}
        :cancelled -> {:cancelled, 1032, "Request cancelled by user", nil}
        :timeout -> {:timeout, 1037, "DS timeout user cannot be reached", nil}
        :failed -> {:failed, 1, "The balance is insufficient for the transaction", nil}
      end

    Agent.update(__MODULE__, &put_in(&1[id].state, {status, code, desc, rcpt}))
    payload = callback_payload(id, st, code, desc, rcpt, amount)
    if Keyword.get(opts, :deliver, true), do: TheGame.Payments.handle_callback(payload)
    payload
  end

  def callback_payload(id, st, code, desc, receipt, amount) do
    meta =
      if code == 0 do
        %{
          "CallbackMetadata" => %{
            "Item" => [
              %{"Name" => "Amount", "Value" => amount},
              %{"Name" => "MpesaReceiptNumber", "Value" => receipt},
              %{"Name" => "TransactionDate", "Value" => eat_now_stamp()},
              %{"Name" => "PhoneNumber", "Value" => String.to_integer(st.phone)}
            ]
          }
        }
      else
        %{}
      end

    %{
      "Body" => %{
        "stkCallback" =>
          Map.merge(
            %{
              "MerchantRequestID" => "mr_fake",
              "CheckoutRequestID" => id,
              "ResultCode" => code,
              "ResultDesc" => desc
            },
            meta
          )
      }
    }
  end

  # Daraja sends TransactionDate as an integer yyyymmddhhmmss in East Africa Time.
  defp eat_now_stamp do
    DateTime.utc_now()
    |> DateTime.add(3 * 3600)
    |> Calendar.strftime("%Y%m%d%H%M%S")
    |> String.to_integer()
  end

  # Dev convenience: config :the_game, TheGame.Mpesa.Fake, auto: {:success, 4000}
  defp maybe_auto(id) do
    case Application.get_env(:the_game, __MODULE__, [])[:auto] do
      {outcome, ms} ->
        Task.start(fn ->
          Process.sleep(ms)
          complete(id, outcome)
        end)

      _ ->
        :ok
    end
  end
end
