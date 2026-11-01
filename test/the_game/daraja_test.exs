defmodule TheGame.DarajaTest do
  use ExUnit.Case, async: false
  alias TheGame.Mpesa.Daraja

  setup do
    old = Application.get_env(:the_game, Daraja)
    :persistent_term.erase({Daraja, :token})

    Application.put_env(:the_game, Daraja,
      base_url: "https://sandbox.example",
      consumer_key: "ck",
      consumer_secret: "cs",
      shortcode: "174379",
      passkey: "pk",
      callback_url: "https://game.example/mpesa/callback/tok",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.put_env(:the_game, Daraja, old || []) end)
    :ok
  end

  test "stk_push builds a correct Daraja request and parses the reply" do
    Req.Test.expect(__MODULE__, 2, fn conn ->
      case conn.request_path do
        "/oauth/v1/generate" ->
          assert ["Basic " <> basic] = Plug.Conn.get_req_header(conn, "authorization")
          assert Base.decode64!(basic) == "ck:cs"
          Req.Test.json(conn, %{"access_token" => "tok123", "expires_in" => "3599"})

        "/mpesa/stkpush/v1/processrequest" ->
          assert ["Bearer tok123"] = Plug.Conn.get_req_header(conn, "authorization")
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          b = Jason.decode!(raw)
          assert b["Amount"] == 2500
          assert b["PartyA"] == "254712345678" and b["PhoneNumber"] == "254712345678"
          assert b["BusinessShortCode"] == "174379" and b["PartyB"] == "174379"
          assert b["TransactionType"] == "CustomerPayBillOnline"
          assert b["CallBackURL"] == "https://game.example/mpesa/callback/tok"
          assert b["AccountReference"] == "K7M2"
          assert Base.decode64!(b["Password"]) == "174379pk" <> b["Timestamp"]
          assert b["Timestamp"] =~ ~r/^\d{14}$/

          Req.Test.json(conn, %{
            "ResponseCode" => "0",
            "CheckoutRequestID" => "ws_CO_1",
            "MerchantRequestID" => "mr_1"
          })
      end
    end)

    assert {:ok, %{checkout_request_id: "ws_CO_1", merchant_request_id: "mr_1"}} =
             Daraja.stk_push(%{
               phone: "254712345678",
               amount: 2500,
               reference: "K7M2",
               description: "THE GAME"
             })
  end

  test "the access token is cached between calls" do
    :persistent_term.put({Daraja, :token}, {"cached", System.system_time(:second) + 3000})

    Req.Test.expect(__MODULE__, 1, fn conn ->
      assert conn.request_path == "/mpesa/stkpush/v1/processrequest"
      assert ["Bearer cached"] = Plug.Conn.get_req_header(conn, "authorization")

      Req.Test.json(conn, %{
        "ResponseCode" => "0",
        "CheckoutRequestID" => "c",
        "MerchantRequestID" => "m"
      })
    end)

    assert {:ok, _} =
             Daraja.stk_push(%{
               phone: "254712345678",
               amount: 100,
               reference: "AAAA",
               description: "x"
             })
  end

  test "a rejected push is an error, never a silent success" do
    :persistent_term.put({Daraja, :token}, {"t", System.system_time(:second) + 3000})

    Req.Test.expect(__MODULE__, 1, fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "errorCode" => "400.002.02",
        "errorMessage" => "Bad Request - Invalid PhoneNumber"
      })
    end)

    assert {:error, {:daraja, %{"errorCode" => "400.002.02"}}} =
             Daraja.stk_push(%{
               phone: "254712345678",
               amount: 100,
               reference: "AAAA",
               description: "x"
             })
  end

  test "stk_query result mapping" do
    ok = fn code, extra ->
      %{status: 200, body: Map.merge(%{"ResultCode" => code, "ResultDesc" => "d"}, extra)}
    end

    assert {:ok, %{status: :success, receipt: "R1", code: 0}} =
             Daraja.parse_query(ok.("0", %{"MpesaReceiptNumber" => "R1"}))

    assert {:ok, %{status: :cancelled, code: 1032}} = Daraja.parse_query(ok.("1032", %{}))
    assert {:ok, %{status: :timeout}} = Daraja.parse_query(ok.("1037", %{}))
    assert {:ok, %{status: :failed}} = Daraja.parse_query(ok.("1", %{}))

    assert {:ok, %{status: :pending}} =
             Daraja.parse_query(%{
               status: 500,
               body: %{
                 "errorCode" => "500.001.1001",
                 "errorMessage" => "The transaction is being processed"
               }
             })

    assert {:error, _} = Daraja.parse_query(%{status: 503, body: "oops"})
  end
end
