defmodule TheGameWeb.MpesaControllerTest do
  use TheGameWeb.ConnCase
  import TheGame.Fixtures
  alias TheGame.{Orders, Payments}
  alias TheGame.Mpesa.Fake

  setup do
    {:ok, o} = Orders.create_order(order_attrs([{product(%{price_cents: 100_000}), 1}]))
    {:ok, p} = Payments.request_stk(o.id)
    {:ok, order: o, pay: p}
  end

  test "rejects a wrong token with 404 and does nothing", %{conn: conn, order: o, pay: p} do
    payload = Fake.complete(p.checkout_request_id, :success, deliver: false)
    conn = post(conn, "/mpesa/callback/wrong", payload)
    assert response(conn, 404)
    assert Orders.get_order!(o.id).status == :pending_payment
  end

  test "accepts a good callback, acks 200, and is replay-safe", %{conn: conn, order: o, pay: p} do
    payload = Fake.complete(p.checkout_request_id, :success, deliver: false, receipt: "CTRL1")
    c1 = post(conn, "/mpesa/callback/test-token", payload)
    assert json_response(c1, 200) == %{"ResultCode" => 0, "ResultDesc" => "Accepted"}
    assert Orders.get_order!(o.id).status == :paid
    c2 = post(build_conn(), "/mpesa/callback/test-token", payload)
    assert json_response(c2, 200)
    assert Orders.get_order!(o.id).status == :paid
  end

  test "garbage bodies still get a 200 (no endless retries) and change nothing", %{
    conn: conn,
    order: o
  } do
    assert conn |> post("/mpesa/callback/test-token", %{"hello" => "world"}) |> json_response(200)
    assert Orders.get_order!(o.id).status == :pending_payment
  end
end
