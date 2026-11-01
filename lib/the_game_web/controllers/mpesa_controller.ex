defmodule TheGameWeb.MpesaController do
  use TheGameWeb, :controller
  require Logger
  alias TheGame.Payments

  @doc """
  Daraja STK callback. The token in the path stands in for a signature Safaricom does not
  provide. Beyond that, `Payments.handle_callback/1` only acts on payments we created and
  is idempotent. We always acknowledge with 200 once the body is understood, so Safaricom
  does not retry endlessly; real failures are logged and caught by reconciliation.
  """
  def callback(conn, %{"token" => token} = params) do
    expected = Application.get_env(:the_game, :mpesa_callback_token)

    if is_binary(expected) and Plug.Crypto.secure_compare(token, expected) do
      case Payments.handle_callback(params) do
        {:error, reason} when reason not in [:unknown_payment] ->
          Logger.error("mpesa callback not applied: #{inspect(reason)}")

        _ ->
          :ok
      end

      json(conn, %{"ResultCode" => 0, "ResultDesc" => "Accepted"})
    else
      send_resp(conn, 404, "")
    end
  end
end
