defmodule TheGameWeb.StaffTest do
  use TheGameWeb.ConnCase
  import Phoenix.LiveViewTest
  import TheGame.Fixtures
  import TheGame.DataCase, only: [errors_on: 1]
  alias TheGame.{Orders, Payments, Repo, Settings, Staff}
  alias TheGame.Mpesa.Fake

  @pw "correct horse battery"

  defp staff!(email \\ "owner#{System.unique_integer([:positive])}@bar.test") do
    {:ok, u} = Staff.create_user(%{email: email, password: @pw})
    u
  end

  defp last4(order), do: Orders.receipt_end(Orders.get_order!(order.id))

  defp as_staff(conn, u), do: init_test_session(conn, %{"staff_id" => u.id})

  defp paid_order(items, phone \\ nil) do
    {:ok, o} = Orders.create_order(order_attrs(items, %{payer_phone: phone || unique_phone()}))
    {:ok, o} = Orders.mark_paid(o.id, "R#{System.unique_integer([:positive])}")
    o
  end

  describe "authentication" do
    test "everything under /staff needs a login", %{conn: conn} do
      for path <- ["/staff", "/staff/reviews", "/staff/menu", "/staff/today"] do
        assert redirected_to(get(conn, path)) == "/staff/login"
      end
    end

    test "the login page is not indexable and not linked from the storefront", %{conn: conn} do
      html = conn |> get("/staff/login") |> html_response(200)
      assert html =~ ~s(content="noindex, nofollow")
      refute conn |> get("/") |> html_response(200) =~ "/staff"
    end

    test "good credentials sign in and renew the session", %{conn: conn} do
      u = staff!("me@bar.test")
      conn = post(conn, "/staff/login", %{"email" => " ME@bar.test ", "password" => @pw})
      assert redirected_to(conn) == "/staff"
      assert get_session(conn, :staff_id) == u.id
    end

    test "wrong password and unknown email look identical", %{conn: conn} do
      staff!("me2@bar.test")
      a = post(conn, "/staff/login", %{"email" => "me2@bar.test", "password" => "nope nope nope"})

      b =
        post(build_conn(), "/staff/login", %{
          "email" => "ghost@bar.test",
          "password" => "nope nope nope"
        })

      assert html_response(a, 401) =~ "Wrong email or password."
      assert html_response(b, 401) =~ "Wrong email or password."
    end

    test "five failures lock that email/client out, even for the right password", %{conn: conn} do
      staff!("lock@bar.test")

      for _ <- 1..5,
          do:
            post(build_conn(), "/staff/login", %{
              "email" => "lock@bar.test",
              "password" => "wrong wrong wrong"
            })

      assert conn
             |> post("/staff/login", %{"email" => "lock@bar.test", "password" => @pw})
             |> html_response(429) =~ "Too many attempts"
    end

    test "passwords must be long, and are stored hashed" do
      assert {:error, cs} = Staff.create_user(%{email: "x@y.test", password: "short"})
      assert %{password: [_]} = errors_on(cs)
      u = staff!()
      assert String.starts_with?(u.password_hash, "$pbkdf2")
      refute u.password_hash =~ @pw
    end

    test "a password can be reset by email; the old one stops working, the new one works" do
      staff!("reset@bar.test")
      assert {:ok, _} = Staff.authenticate("reset@bar.test", @pw)
      assert {:ok, _} = Staff.set_password(" RESET@bar.test ", "Game1234")
      assert {:error, :invalid} = Staff.authenticate("reset@bar.test", @pw)
      assert {:ok, _} = Staff.authenticate("reset@bar.test", "Game1234")
      assert {:error, :not_found} = Staff.set_password("nobody@bar.test", "Game1234")
      assert {:error, cs} = Staff.set_password("reset@bar.test", "short")
      assert %{password: [_]} = errors_on(cs)
    end

    test "a deactivated account is cut off immediately", %{conn: conn} do
      u = staff!()
      assert {:ok, _, _} = live(as_staff(conn, u), "/staff")
      u |> Ecto.Changeset.change(active: false) |> Repo.update!()
      assert redirected_to(get(as_staff(build_conn(), u), "/staff")) == "/staff/login"
    end

    test "sign out clears the session", %{conn: conn} do
      conn = conn |> as_staff(staff!()) |> post("/staff/logout")
      assert redirected_to(conn) == "/staff/login"
    end
  end

  describe "queue board" do
    setup %{conn: conn} do
      {:ok, conn: as_staff(conn, staff!()), gin: product(%{name: "Gin"})}
    end

    test "a paid order appears live and moves through the bar to delivered", %{
      conn: conn,
      gin: gin
    } do
      {:ok, view, _} = live(conn, "/staff")
      refute render(view) =~ "Gin"

      o = paid_order([{gin, 2}])
      html = render(view)
      assert html =~ o.pickup_code
      assert html =~ "2×"

      # the customer's own page follows along
      {:ok, cust, _} = live(build_conn(), ~p"/order/#{o.id}")

      view |> element(~s(#o-#{o.id} button), "Start") |> render_click()
      assert render(cust) =~ "Being prepared"
      view |> element(~s(#o-#{o.id} button), "Ready") |> render_click()
      assert render(cust) =~ "Ready. Your waiter will bring it"
      view |> element(~s(#o-#{o.id} button), "Delivered") |> render_click()
      assert render(cust) =~ "Delivered. Enjoy"
      refute render(view) =~ ~s(id="o-#{o.id}")
    end

    test "illegal or forged moves are refused and change nothing", %{conn: conn, gin: gin} do
      o = paid_order([{gin, 1}])
      {:ok, view, _} = live(conn, "/staff")
      html = render_click(view, "advance", %{"id" => o.id, "to" => "paid"})
      assert html =~ "can’t move there"
      render_click(view, "advance", %{"id" => o.id, "to" => "closed"})
      assert Orders.get_order!(o.id).status == :paid
    end

    test "find an order by pickup code, any status", %{conn: conn, gin: gin} do
      o = paid_order([{gin, 1}])
      Orders.transition(o.id, :preparing)
      Orders.transition(o.id, :ready)
      Orders.transition(o.id, :completed)
      {:ok, view, _} = live(conn, "/staff")

      html =
        view
        |> form("form[phx-change=find]", %{"code" => String.downcase(o.pickup_code)})
        |> render_change()

      assert html =~ o.pickup_code
      assert html =~ "Delivered"
    end

    test "waiter writes the code and time from the client's phone; first wins; delivered closes it",
         %{conn: conn, gin: gin} do
      o = paid_order([{gin, 1}])
      actual = last4(o)
      {:ok, view, _} = live(conn, "/staff")
      {:ok, other, _} = live(conn, "/staff")

      claim = fn v, c, t ->
        v |> form("#o-#{o.id} form.claimform", %{"last4" => c, "time" => t}) |> render_submit()
      end

      # the card already shows the order's actual last 4 for the counter to match against
      assert render(view) =~ ~s(<b class="mono">#{actual}</b>)

      # missing pieces are asked for, and nothing is claimed
      assert claim.(view, actual, "16:52") =~ "Type your name"
      render_hook(view, "set_waiter", %{"waiter" => "Amina"})
      html = claim.(view, "", "16:52")
      assert html =~ "last 4 characters"
      assert html =~ ~s(value="16:52")
      assert claim.(view, actual, "") =~ "Type the time paid"
      assert Orders.get_order!(o.id).claimed_by_name == nil

      html = claim.(view, String.downcase(actual), "4:52 PM")
      assert html =~ "You have this"
      assert html =~ "Amina wrote"
      assert html =~ "#{actual}<i>·</i>4:52 PM"
      assert html =~ "code matches"
      assert Orders.get_order!(o.id).recorded_time == "4:52 PM"

      # a second waiter sees who has it, and cannot take it
      assert render(other) =~ "Amina has this"
      render_hook(other, "set_waiter", %{"waiter" => "Brian"})

      assert render_hook(other, "claim", %{"oid" => o.id, "last4" => actual, "time" => "10:00"}) =~
               "Amina already has that order"

      view |> element(~s(#o-#{o.id} button), "Delivered") |> render_click()
      assert Orders.get_order!(o.id).status == :completed
    end

    test "a code that differs from the order's is recorded and flagged for the counter, not refused",
         %{conn: conn, gin: gin} do
      o = paid_order([{gin, 1}])
      {:ok, view, _} = live(conn, "/staff")
      render_hook(view, "set_waiter", %{"waiter" => "Amina"})

      html =
        view
        |> form("#o-#{o.id} form.claimform", %{"last4" => "ZZZZ", "time" => "16:52"})
        |> render_submit()

      assert html =~ "Amina wrote"
      assert html =~ "code differs"
      assert Orders.get_order!(o.id).recorded_code == "ZZZZ"
    end

    test "till payment: unpaid order -> waiter writes the code -> confirmed at counter -> bar -> delivered",
         %{conn: conn, gin: gin} do
      {:ok, o} = Orders.create_order(order_attrs([{gin, 2}], %{payer_phone: "0712 345 678"}))
      {:ok, view, html} = live(conn, "/staff")
      {:ok, cust, _} = live(build_conn(), ~p"/order/#{o.id}")

      # it shows in its own section with the client's number ending, not in New
      assert html =~ "Waiting for payment"
      assert html =~ o.pickup_code
      assert html =~ "Unpaid"
      assert html =~ "…<b class=\"mono\">5678</b>"
      refute html =~ "Confirmed at counter"

      # she must say who she is and what she saw before anything else
      render_hook(view, "set_waiter", %{"waiter" => "Amina"})

      assert render_click(view, "confirm_till", %{"id" => o.id}) =~
               "Write the client’s M-Pesa code and time first"

      assert Orders.get_order!(o.id).status == :pending_payment

      html =
        view
        |> form("#o-#{o.id} form.claimform", %{"last4" => "k932", "time" => "4:52 PM"})
        |> render_submit()

      # her card shows the drinks, the amount, the time and the code she wrote down
      assert html =~ "Amount due"
      assert html =~ "Time paid"
      assert html =~ ~s(<b class="mono">4:52 PM</b>)
      assert html =~ "M-Pesa code"
      assert html =~ ~s(<b class="mono">K932</b>)
      assert html =~ "Recorded by <b>Amina</b>"
      assert html =~ "Confirmed at counter"
      refute html =~ "code differs"
      assert render(cust) =~ "has your payment details and is confirming your payment"

      # the counter confirmed on the POS: one tap, and it is paid and in the bar's New list
      html = view |> element(~s(#o-#{o.id} button), "Confirmed at counter") |> render_click()
      assert Orders.get_order!(o.id).status == :paid
      assert Orders.get_order!(o.id).confirmed_by_name == "Amina"
      refute html =~ "Waiting for payment"
      assert html =~ "Amount paid"
      assert html =~ ~s(<b class="mono">K932</b>)
      assert html =~ ~s(<b class="mono">4:52 PM</b>)
      assert html =~ "confirmed at counter"
      assert render(cust) =~ "Paid. The bar has your order"

      view |> element(~s(#o-#{o.id} button), "Start") |> render_click()
      view |> element(~s(#o-#{o.id} button), "Ready") |> render_click()
      assert render(cust) =~ "Ready. Amina will bring it"
      view |> element(~s(#o-#{o.id} button), "Delivered") |> render_click()
      assert Orders.get_order!(o.id).status == :completed
    end

    test "an expired unpaid order is still shown (the client may have paid) and can be confirmed",
         %{conn: conn, gin: gin} do
      {:ok, o} = Orders.create_order(order_attrs([{gin, 1}], %{payer_phone: unique_phone()}))
      Orders.expire_due(DateTime.add(DateTime.utc_now(), 7200))
      {:ok, view, html} = live(conn, "/staff")
      assert html =~ "Expired"

      render_hook(view, "set_waiter", %{"waiter" => "Amina"})

      view
      |> form("#o-#{o.id} form.claimform", %{"last4" => "K932", "time" => "16:52"})
      |> render_submit()

      view |> element(~s(#o-#{o.id} button), "Confirmed at counter") |> render_click()
      assert Orders.get_order!(o.id).status == :paid
    end

    test "give back lets another waiter take it", %{conn: conn, gin: gin} do
      o = paid_order([{gin, 1}])
      {:ok, view, _} = live(conn, "/staff")
      render_hook(view, "set_waiter", %{"waiter" => "Amina"})

      view
      |> form("#o-#{o.id} form.claimform", %{"last4" => last4(o), "time" => "16:52"})
      |> render_submit()

      view |> element(~s(#o-#{o.id} button), "Give back") |> render_click()
      assert Orders.get_order!(o.id).claimed_by_name == nil
    end

    test "lookup by the ending of the M-Pesa code finds the order", %{conn: conn, gin: gin} do
      o = paid_order([{gin, 2}])
      receipt = Orders.get_order!(o.id).mpesa_receipt
      {:ok, view, html} = live(conn, "/staff")
      assert html =~ "KES 2,000"

      ending = String.slice(receipt, -5, 5)

      html =
        view
        |> form("form[phx-change=find]", %{"code" => String.downcase(ending)})
        |> render_change()

      assert html =~ "Found"
      assert html =~ o.pickup_code
    end

    test "pause toggle blocks checkout for customers and shows on their menu", %{
      conn: conn,
      gin: gin
    } do
      category("Spirits", [gin])
      {:ok, view, _} = live(conn, "/staff")
      assert render(view) =~ "Taking orders"
      html = view |> element("button.switch") |> render_click()
      assert html =~ "Ordering paused"
      assert Settings.ordering_paused?()
      assert build_conn() |> get("/") |> html_response(200) =~ "Ordering is paused"

      assert {:error, :ordering_paused} = Orders.create_order(order_attrs([{gin, 1}]))
      view |> element("button.switch") |> render_click()
      refute Settings.ordering_paused?()
    end
  end

  describe "payment reviews" do
    setup %{conn: conn} do
      gin = product(%{stock: 5})
      {:ok, o} = Orders.create_order(order_attrs([{gin, 1}]))
      {:ok, p} = Payments.request_stk(o.id)
      Orders.expire_due(DateTime.add(DateTime.utc_now(), 3600))
      Fake.complete(p.checkout_request_id, :success, receipt: "STAFF1")
      {:ok, conn: as_staff(conn, staff!()), order: o}
    end

    test "late payment is listed with its facts", %{conn: conn, order: o} do
      {:ok, view, html} = live(conn, "/staff/reviews")
      assert html =~ o.pickup_code
      assert html =~ "Paid after the order expired"
      assert html =~ "STAFF1"
      assert render(view) =~ "Honour: send to bar"
    end

    test "honouring needs a confirmation, then sends the order to the bar", %{
      conn: conn,
      order: o
    } do
      {:ok, view, _} = live(conn, "/staff/reviews")
      view |> element("button", "Honour: send to bar") |> render_click()
      assert render(view) =~ "Accept this payment"
      assert Orders.get_order!(o.id).status == :flagged
      view |> element("button", "Yes") |> render_click()
      assert Orders.get_order!(o.id).status == :preparing
      assert render(view) =~ "All clear"
    end

    test "refund closes the order", %{conn: conn, order: o} do
      {:ok, view, _} = live(conn, "/staff/reviews")
      view |> element("button", "Refunded / dismiss") |> render_click()
      view |> element("button", "Yes") |> render_click()
      assert Orders.get_order!(o.id).status == :closed
    end

    test "the board points staff at flagged orders and the nav shows the count", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/staff")
      assert html =~ "Needs you"
      assert html =~ ~s(<span class="count">1</span>)
    end
  end

  describe "menu and stock" do
    setup %{conn: conn} do
      p = product(%{name: "Vodka", price_cents: 150_000, stock: 3})
      cat = category("Spirits", [p])
      {:ok, conn: as_staff(conn, staff!()), p: p, cat: cat}
    end

    test "setting stock to 0 sells the item out on customers' menus", %{conn: conn, p: p} do
      {:ok, view, _} = live(conn, "/staff/menu")

      view
      |> form("#p-#{p.id} form", %{"price" => "1500", "stock" => "0", "active" => "true"})
      |> render_submit()

      assert Repo.reload!(p).stock == 0
      assert build_conn() |> get("/") |> html_response(200) =~ "Sold out"
    end

    test "hiding a product removes it from the menu and the feed", %{conn: conn, p: p} do
      {:ok, view, _} = live(conn, "/staff/menu")

      # an unchecked checkbox is simply absent from a browser's form submission
      render_hook(view, "save", %{"pid" => p.id, "price" => "1500", "stock" => "3"})

      refute build_conn() |> get("/") |> html_response(200) =~ "Vodka"
      refute json_response(get(build_conn(), "/menu.json"), 200)["p"][p.id]
    end

    test "blank stock means not counted; junk price is rejected", %{conn: conn, p: p} do
      {:ok, view, _} = live(conn, "/staff/menu")

      view
      |> form("#p-#{p.id} form", %{"price" => "1500", "stock" => "", "active" => "true"})
      |> render_submit()

      assert Repo.reload!(p).stock == nil

      html =
        view
        |> form("#p-#{p.id} form", %{"price" => "abc", "stock" => "", "active" => "true"})
        |> render_submit()

      assert html =~ "Price"
      assert Repo.reload!(p).price_cents == 150_000
    end

    test "a new product appears on the menu", %{conn: conn, cat: cat} do
      {:ok, view, _} = live(conn, "/staff/menu")

      view
      |> form("form.pform", %{
        "name" => "Gin Tonic",
        "price" => "650",
        "category" => cat.id,
        "stock" => ""
      })
      |> render_submit()

      html = build_conn() |> get("/") |> html_response(200)
      assert html =~ "Gin Tonic"
      assert html =~ "KES 650"
    end
  end

  describe "today" do
    test "totals and best sellers", %{conn: conn} do
      gin = product(%{name: "Gin", price_cents: 100_000})
      paid_order([{gin, 2}])
      paid_order([{gin, 1}])
      {:ok, _, html} = live(as_staff(conn, staff!()), "/staff/today")
      assert html =~ "KES 3,000"
      assert html =~ "Gin"
      assert html =~ ">3<"
    end
  end
end
