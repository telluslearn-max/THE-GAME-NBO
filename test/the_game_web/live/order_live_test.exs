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

  # The browser that just checked out carries the signed `fresh_order` session flag.
  defp live_fresh(conn, o),
    do: live(init_test_session(conn, %{"fresh_order" => o.id}), ~p"/order/#{o.id}")

  describe "pay by till (the main way to pay)" do
    setup do
      Application.put_env(:the_game, :auto_prompt, false)
      on_exit(fn -> Application.put_env(:the_game, :auto_prompt, true) end)
    end

    test "shows the till number, the exact amount, copy buttons and the client's code; no prompt is sent",
         %{conn: conn, order: o} do
      {:ok, view, _} = live_fresh(conn, o)
      html = render(view)
      assert html =~ "Pay by till"
      assert html =~ "Buy Goods"
      assert html =~ ~s(data-copy="111222")
      assert html =~ "KES 2,500"
      assert html =~ ~s(data-copy="2500")
      assert html =~ ~s(phx-hook="Copy")
      assert html =~ "Order reference"
      assert html =~ o.pickup_code
      # the client is never told to give a code to the waiter: she writes the M-Pesa code and time
      refute html =~ "tell your waiter your code"
      refute html =~ "Give this code"
      assert html =~ "show your waiter this page and your M-Pesa message"
      assert html =~ "Don’t pay this till number again"
      assert html =~ "Already paid? Don’t pay again."
      # a visible Cancel section with the warnings
      assert html =~ "Cancel this order"
      assert html =~ "Only cancel if you <b>haven’t paid</b>"
      assert html =~ "Don’t enter your PIN for this order after cancelling"
      # prompting is only an option, never automatic
      assert html =~ "Prefer a prompt on your phone?"
      assert Repo.aggregate(Payments.Payment, :count) == 0
    end

    test "when the waiter takes the code and the counter confirms, the client's page follows live",
         %{conn: conn, order: o} do
      {:ok, view, _} = live_fresh(conn, o)
      refute render(view) =~ "is confirming your payment"

      {:ok, _} = Orders.claim(o.id, "Amina", "K932", "16:52")

      assert render(view) =~
               "<b>Amina</b> has your payment details and is confirming your payment"

      {:ok, _} = Orders.confirm_till(o.id, "Amina")
      html = render(view)
      assert html =~ "Paid. The bar has your order"
      assert html =~ "You’ll be served by <b>Amina</b>"
      assert html =~ "Payment confirmed at the till"
      refute html =~ "Pay by till"
      refute html =~ "Cancel this order"
      assert html =~ "Order reference"
    end

    test "without a till number configured, the page falls back to the prompt", %{
      conn: conn,
      order: o
    } do
      old = Application.get_env(:the_game, :till_number)
      Application.put_env(:the_game, :till_number, nil)
      on_exit(fn -> Application.put_env(:the_game, :till_number, old) end)
      {:ok, view, _} = live_fresh(conn, o)
      html = render(view)
      refute html =~ "Pay by till"
      assert html =~ "Send me an M-Pesa prompt"
    end

    test "till-only deployments (no gateway) never offer a prompt", %{conn: conn, order: o} do
      old = Application.get_env(:the_game, :mpesa_adapter)
      Application.put_env(:the_game, :mpesa_adapter, nil)
      on_exit(fn -> Application.put_env(:the_game, :mpesa_adapter, old) end)
      {:ok, view, _} = live_fresh(conn, o)
      html = render(view)
      assert html =~ "Pay by till"
      refute html =~ "Send me an M-Pesa prompt"
      assert {:error, :stk_disabled} = Payments.request_stk(o.id)
    end
  end

  describe "cancelling" do
    setup do
      Application.put_env(:the_game, :auto_prompt, false)
      on_exit(fn -> Application.put_env(:the_game, :auto_prompt, true) end)
    end

    test "needs a confirmation, releases the drinks, and warns not to pay after cancelling", %{
      conn: conn,
      order: o,
      gin: gin
    } do
      {:ok, view, _} = live_fresh(conn, o)
      html = view |> element("button", "Cancel order") |> render_click()
      assert html =~ "Cancel this unpaid order?"
      assert html =~ "don’t pay again"
      html = view |> element("button", "Yes, cancel") |> render_click()
      assert html =~ "Order cancelled"
      refute html =~ "Pay by till"
      assert Repo.reload!(gin).stock == 9
    end

    test "once a waiter has the client's payment details, cancelling is not offered and is refused",
         %{conn: conn, order: o} do
      {:ok, view, _} = live_fresh(conn, o)
      {:ok, _} = Orders.claim(o.id, "Amina", "K932", "16:52")
      html = render(view)
      assert html =~ "already has your payment details"
      refute html =~ "Yes, cancel"
      assert {:error, :claimed} = Orders.cancel(o.id)
      assert Orders.get_order!(o.id).status == :pending_payment
    end
  end

  test "unknown order shows a calm not-found page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/order/#{Ecto.UUID.generate()}")
    assert html =~ "Order not found"
  end

  test "first arrival sends the M-Pesa prompt automatically, exactly once", %{
    conn: conn,
    order: o
  } do
    {:ok, view, _} = live_fresh(conn, o)
    html = render(view)
    assert html =~ "Check your phone"
    assert html =~ "5678"
    assert Repo.aggregate(Payments.Payment, :count) == 1

    # a reload (or reconnect) must not prompt again
    {:ok, view2, _} = live_fresh(conn, o)
    render(view2)
    assert Repo.aggregate(Payments.Payment, :count) == 1
  end

  test "a stranger holding the link never triggers a prompt", %{conn: conn, order: o} do
    {:ok, view, _} = live(conn, ~p"/order/#{o.id}")
    html = render(view)
    assert html =~ "Send me an M-Pesa prompt"
    refute html =~ "Check your phone"
    assert Repo.aggregate(Payments.Payment, :count) == 0
  end

  test "payment confirmation reaches the page live and reveals the pickup code", %{
    conn: conn,
    order: o
  } do
    {:ok, view, html} = live_fresh(conn, o)
    assert html =~ "Order reference"
    assert html =~ ~s(data-status="pending_payment")
    render(view)
    p = Payments.latest_payment(o.id)

    Fake.complete(p.checkout_request_id, :success, receipt: "LIVE1")
    html = render(view)
    assert html =~ "Paid. The bar has your order"
    assert html =~ "Order reference"
    assert html =~ "LIVE1"
    refute html =~ "Check your phone"
  end

  test "staff moving the order reaches the customer without a reload", %{conn: conn, order: o} do
    {:ok, view, _} = live_fresh(conn, o)
    Orders.mark_paid(o.id, "STF1")
    Orders.transition(o.id, :preparing)
    assert render(view) =~ "Being prepared"
    Orders.transition(o.id, :ready)
    html = render(view)
    assert html =~ "Ready. Your waiter will bring it"
    assert html =~ ~s(data-status="ready")
    assert html =~ "ticket go"
  end

  test "the customer sees which waiter will serve them, live, and who delivered", %{
    conn: conn,
    order: o
  } do
    {:ok, view, html} = live(conn, ~p"/order/#{o.id}")
    refute html =~ "You’ll be served by"
    Orders.mark_paid(o.id, "SRV1")
    refute render(view) =~ "You’ll be served by"

    {:ok, _} = Orders.claim(o.id, "Amina", "SRV1", "12:00")
    assert render(view) =~ "You’ll be served by <b>Amina</b>"

    Orders.transition(o.id, :ready)
    assert render(view) =~ "Ready. Amina will bring it"

    {:ok, _} = Orders.deliver(o.id)
    html = render(view)
    assert html =~ "Delivered by Amina. Enjoy"
    refute html =~ "You’ll be served by"
  end

  test "a cancelled prompt offers a retry, and retry works", %{conn: conn, order: o} do
    {:ok, view, _} = live_fresh(conn, o)
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
    {:ok, view, _} = live_fresh(conn, o)
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
    {:ok, view, _} = live_fresh(conn, o)
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
    {:ok, view, _} = live_fresh(conn, o)
    render(view)
    p = Payments.latest_payment(o.id)
    Orders.expire_due(DateTime.add(DateTime.utc_now(), 3600))
    Fake.complete(p.checkout_request_id, :success, receipt: "LATE9")
    html = render(view)
    assert html =~ "Staff are checking your payment"
    assert html =~ "Please don’t pay again"
    assert html =~ "Order reference"
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
