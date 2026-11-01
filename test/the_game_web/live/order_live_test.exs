defmodule TheGameWeb.OrderLiveTest do
  use TheGameWeb.ConnCase
  import Phoenix.LiveViewTest
  import TheGame.Fixtures
  alias TheGame.{Orders, Payments, Repo}
  alias TheGame.Mpesa.Fake

  setup do
    Application.put_env(:the_game, :stk_cooldown_seconds, 60)
    on_exit(fn -> Application.put_env(:the_game, :stk_cooldown_seconds, 0) end)
    gin = product(%{name: "Gin", price_cents: 125_000, stock: 9})
    {:ok, order} = Orders.create_order(order_attrs([{gin, 2}]))
    {:ok, order: order, gin: gin}
  end

  test "unknown order shows a calm not-found page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/order/#{Ecto.UUID.generate()}")
    assert html =~ "Order not found"
  end

  test "first arrival sends the M-Pesa prompt automatically, exactly once", %{
    conn: conn,
    order: o
  } do
    {:ok, view, _} = live(conn, ~p"/order/#{o.id}")
    html = render(view)
    assert html =~ "Check your phone"
    assert html =~ "5678"
    assert Repo.aggregate(Payments.Payment, :count) == 1

    # a reload (or reconnect) must not prompt again
    {:ok, view2, _} = live(conn, ~p"/order/#{o.id}")
    render(view2)
    assert Repo.aggregate(Payments.Payment, :count) == 1
  end

  test "payment confirmation reaches the page live and reveals the pickup code", %{
    conn: conn,
    order: o
  } do
    {:ok, view, html} = live(conn, ~p"/order/#{o.id}")
    assert html =~ "Reference"
    assert html =~ ~s(data-status="pending_payment")
    render(view)
    p = Payments.latest_payment(o.id)

    Fake.complete(p.checkout_request_id, :success, receipt: "LIVE1")
    html = render(view)
    assert html =~ "Paid. The bar has your order"
    assert html =~ "Pickup code"
    assert html =~ "LIVE1"
    refute html =~ "Check your phone"
  end

  test "staff moving the order reaches the customer without a reload", %{conn: conn, order: o} do
    {:ok, view, _} = live(conn, ~p"/order/#{o.id}")
    Orders.mark_paid(o.id, "STF1")
    Orders.transition(o.id, :preparing)
    assert render(view) =~ "Being prepared"
    Orders.transition(o.id, :ready)
    html = render(view)
    assert html =~ "Ready. Collect at the bar"
    assert html =~ ~s(data-status="ready")
    assert html =~ "ticket go"
  end

  test "a cancelled prompt offers a retry, and retry works", %{conn: conn, order: o} do
    {:ok, view, _} = live(conn, ~p"/order/#{o.id}")
    render(view)
    Fake.complete(Payments.latest_payment(o.id).checkout_request_id, :cancelled)
    html = render(view)
    assert html =~ "You cancelled the prompt"
    assert html =~ "Send M-Pesa prompt again"
    html = view |> element("button", "Send M-Pesa prompt again") |> render_click()
    assert html =~ "Check your phone"
  end

  test "unresolved prompt: copy says don't pay again, and Check payment settles it", %{
    conn: conn,
    order: o
  } do
    Application.put_env(:the_game, :stk_cooldown_seconds, 0)
    {:ok, view, _} = live(conn, ~p"/order/#{o.id}")
    html = render(view)
    assert html =~ "haven’t heard back from M-Pesa"
    assert Payments.latest_payment(o.id).checkout_request_id
    assert html =~ "don’t pay again"

    html = view |> element("button", "Check payment") |> render_click()
    assert html =~ "Still unconfirmed"

    Fake.complete(Payments.latest_payment(o.id).checkout_request_id, :success,
      deliver: false,
      receipt: "CHK1"
    )

    html = view |> element("button", "Check payment") |> render_click()
    assert html =~ "Paid. The bar has your order"
  end

  test "cancelling needs a confirmation and releases the drinks", %{
    conn: conn,
    order: o,
    gin: gin
  } do
    {:ok, view, _} = live(conn, ~p"/order/#{o.id}")
    assert render(view) =~ "Cancel order"

    assert view |> element("button", "Cancel order") |> render_click() =~
             "Cancel this unpaid order?"

    html = view |> element("button", "Yes, cancel") |> render_click()
    assert html =~ "Order cancelled"
    assert Repo.reload!(gin).stock == 9
  end

  test "late payment shows the staff-verification message, never a pickup code", %{
    conn: conn,
    order: o
  } do
    {:ok, view, _} = live(conn, ~p"/order/#{o.id}")
    render(view)
    p = Payments.latest_payment(o.id)
    Orders.expire_due(DateTime.add(DateTime.utc_now(), 3600))
    Fake.complete(p.checkout_request_id, :success, receipt: "LATE9")
    html = render(view)
    assert html =~ "Staff are checking your payment"
    assert html =~ "Please don’t pay again"
    assert html =~ "Reference"
    refute html =~ "Pickup code"
  end

  describe "orders list and menu banner" do
    setup %{conn: conn, gin: gin} do
      c =
        post(conn, ~p"/orders", %{
          "items" => Jason.encode!([%{id: gin.id, q: 1}]),
          "expected_total" => "125000",
          "phone" => "0799 111 222"
        })

      cookie = c.resp_cookies["tg_orders"].value
      {:ok, mine: put_req_header(build_conn(), "cookie", "tg_orders=#{cookie}")}
    end

    test "lists this browser's orders and nobody else's", %{mine: mine} do
      html = mine |> get(~p"/orders") |> html_response(200)
      assert html =~ "Unpaid"
      assert html =~ "1× Gin"

      assert build_conn() |> get(~p"/orders") |> html_response(200) =~
               "No orders on this phone yet"
    end

    test "the menu offers to continue an unpaid order, only to its owner", %{mine: mine} do
      assert mine |> get(~p"/") |> html_response(200) =~ "Unpaid order"
      refute build_conn() |> get(~p"/") |> html_response(200) =~ "Unpaid order"
    end
  end
end
