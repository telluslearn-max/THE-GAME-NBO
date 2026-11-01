defmodule TheGame.Mpesa.Daraja do
  @moduledoc """
  Safaricom Daraja (M-Pesa Express / STK push) adapter.

  Complete against the public Daraja documentation and covered by request-shape tests,
  but NOT yet exercised against live Safaricom credentials. Run it against the Daraja
  sandbox before go-live.

  Config (`config :the_game, TheGame.Mpesa.Daraja, ...`, filled from env in runtime.exs):
  `base_url`, `consumer_key`, `consumer_secret`, `shortcode`, `passkey`, `callback_url`,
  `transaction_type` ("CustomerPayBillOnline" for Paybill, "CustomerBuyGoodsOnline" for a Till),
  `party_b` (till number when different from shortcode), `req_options` (tests).
  """
  @behaviour TheGame.Mpesa

  @token_key {__MODULE__, :token}

  @impl true
  def stk_push(%{phone: phone, amount: amount, reference: ref, description: desc}) do
    cfg = cfg()
    {ts, password} = password(cfg)

    body = %{
      "BusinessShortCode" => cfg[:shortcode],
      "Password" => password,
      "Timestamp" => ts,
      "TransactionType" => cfg[:transaction_type] || "CustomerPayBillOnline",
      "Amount" => amount,
      "PartyA" => phone,
      "PartyB" => cfg[:party_b] || cfg[:shortcode],
      "PhoneNumber" => phone,
      "CallBackURL" => cfg[:callback_url],
      "AccountReference" => String.slice(ref, 0, 12),
      "TransactionDesc" => String.slice(desc, 0, 13)
    }

    with {:ok, token} <- token(cfg),
         {:ok, %{status: 200, body: %{"ResponseCode" => "0"} = b}} <-
           post(cfg, "/mpesa/stkpush/v1/processrequest", body, token) do
      {:ok,
       %{checkout_request_id: b["CheckoutRequestID"], merchant_request_id: b["MerchantRequestID"]}}
    else
      {:ok, %{body: b}} -> {:error, {:daraja, b}}
      {:error, _} = e -> e
    end
  end

  @impl true
  def stk_query(checkout_request_id) do
    cfg = cfg()
    {ts, password} = password(cfg)

    body = %{
      "BusinessShortCode" => cfg[:shortcode],
      "Password" => password,
      "Timestamp" => ts,
      "CheckoutRequestID" => checkout_request_id
    }

    with {:ok, token} <- token(cfg),
         {:ok, resp} <- post(cfg, "/mpesa/stkpushquery/v1/query", body, token) do
      parse_query(resp)
    end
  end

  @doc false
  # "The transaction is being processed" comes back as an HTTP 500 with errorCode 500.001.1001.
  def parse_query(%{body: %{"errorCode" => "500.001.1001"}}), do: {:ok, %{status: :pending}}

  def parse_query(%{status: 200, body: %{"ResultCode" => code} = b}) do
    code = to_int(code)
    status = TheGame.Mpesa.classify(code)
    {:ok, %{status: status, code: code, desc: b["ResultDesc"], receipt: b["MpesaReceiptNumber"]}}
  end

  def parse_query(%{body: b}), do: {:error, {:daraja, b}}

  defp to_int(i) when is_integer(i), do: i
  defp to_int(s) when is_binary(s), do: String.to_integer(s)

  defp password(cfg) do
    ts = Calendar.strftime(DateTime.add(DateTime.utc_now(), 3 * 3600), "%Y%m%d%H%M%S")
    {ts, Base.encode64(cfg[:shortcode] <> cfg[:passkey] <> ts)}
  end

  defp token(cfg) do
    now = System.system_time(:second)

    case :persistent_term.get(@token_key, nil) do
      {tok, exp} when exp > now + 30 ->
        {:ok, tok}

      _ ->
        opts =
          [
            url: cfg[:base_url] <> "/oauth/v1/generate",
            params: [grant_type: "client_credentials"],
            auth: {:basic, "#{cfg[:consumer_key]}:#{cfg[:consumer_secret]}"},
            receive_timeout: 10_000,
            retry: false
          ] ++ (cfg[:req_options] || [])

        case Req.get(opts) do
          {:ok, %{status: 200, body: %{"access_token" => t, "expires_in" => e}}} ->
            :persistent_term.put(@token_key, {t, now + to_int(e)})
            {:ok, t}

          {:ok, %{body: b}} ->
            {:error, {:daraja_auth, b}}

          {:error, e} ->
            {:error, e}
        end
    end
  end

  # Never retry: a retried STK push could prompt (and charge) the customer twice.
  defp post(cfg, path, body, token) do
    Req.post(
      [
        url: cfg[:base_url] <> path,
        json: body,
        auth: {:bearer, token},
        receive_timeout: 15_000,
        retry: false
      ] ++ (cfg[:req_options] || [])
    )
  end

  defp cfg, do: Application.fetch_env!(:the_game, __MODULE__)
end
