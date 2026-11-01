defmodule TheGame.Mpesa do
  @moduledoc """
  The only door to Safaricom. Everything else talks to this behaviour, so the payment
  state machine is tested against `TheGame.Mpesa.Fake` and production uses
  `TheGame.Mpesa.Daraja`.
  """
  @type push :: %{
          phone: String.t(),
          amount: pos_integer,
          reference: String.t(),
          description: String.t()
        }
  @type push_result :: %{checkout_request_id: String.t(), merchant_request_id: String.t()}
  @type query_result ::
          %{status: :pending}
          | %{
              status: :success | :failed | :cancelled | :timeout,
              code: integer,
              desc: String.t(),
              receipt: String.t() | nil
            }

  @callback stk_push(push) :: {:ok, push_result} | {:error, term}
  @callback stk_query(checkout_request_id :: String.t()) :: {:ok, query_result} | {:error, term}

  @doc "nil when the deployment is till-only (MPESA_ADAPTER=none): no prompts are sent."
  def adapter, do: Application.get_env(:the_game, :mpesa_adapter)
  def enabled?, do: adapter() != nil
  def stk_push(p), do: adapter().stk_push(p)
  def stk_query(id), do: adapter().stk_query(id)

  @doc "Map a Daraja ResultCode to our status."
  def classify(0), do: :success
  def classify(1032), do: :cancelled
  def classify(1037), do: :timeout
  def classify(_), do: :failed
end
