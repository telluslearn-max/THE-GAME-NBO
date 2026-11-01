defmodule TheGameWeb.InsightsLiveTest do
  use TheGameWeb.ConnCase
  import Phoenix.LiveViewTest
  import TheGame.Fixtures
  import Ecto.Query, only: [from: 2]
  alias TheGame.{Catalog, Orders, Repo, Staff}

  defp user!(role) do
    {:ok, u} =
      Staff.create_user(%{
        email: "#{role}#{System.unique_integer([:positive])}@bar.test",
        password: "correct horse battery",
        role: role
      })

    u
  end

  defp as(conn, u), do: init_test_session(conn, %{"staff_id" => u.id})

  describe "access" do
    test "admins see Insights; ordinary staff are sent back to the board and never see it", %{
      conn: conn
    } do
      admin = user!(:admin)
      staff = user!(:staff)

      assert {:ok, _view, html} = live(as(conn, admin), "/staff/insights")
      assert html =~ "Insights"
      assert html =~ "Revenue"

      assert {:error, {:live_redirect, %{to: "/staff"}}} =
               live(as(build_conn(), staff), "/staff/insights")

      # the nav link is for admins only
      {:ok, _, staff_board} = live(as(build_conn(), staff), "/staff")
      refute staff_board =~ ~s(href="/staff/insights")
      {:ok, _, admin_board} = live(as(build_conn(), admin), "/staff")
      assert admin_board =~ ~s(href="/staff/insights")
    end

    test "logged-out visitors are sent to the login", %{conn: conn} do
      assert redirected_to(get(conn, "/staff/insights")) == "/staff/login"
    end

    test "admins land on Insights after signing in; staff land on the board", %{conn: conn} do
      admin = user!(:admin)
      staff = user!(:staff)
      pw = "correct horse battery"

      assert redirected_to(
               post(conn, "/staff/login", %{"email" => admin.email, "password" => pw})
             ) == "/staff/insights"

      assert redirected_to(
               post(build_conn(), "/staff/login", %{"email" => staff.email, "password" => pw})
             ) == "/staff"
    end

    test "a role can't be chosen from the login form or the web: new accounts are staff unless set in code" do
      {:ok, u} = Staff.create_user(%{email: "plain@bar.test", password: "correct horse battery"})
      assert u.role == :staff
      refute Staff.admin?(u)
      assert Staff.admin?(user!(:admin))
    end
  end

  describe "the page" do
    setup %{conn: conn} do
      gin = product(%{name: "Gin", price_cents: 100_000})
      cold = product(%{name: "Cold Seller", price_cents: 50_000})
      low = product(%{name: "Nearly Out", price_cents: 20_000, stock: 1})
      {:ok, o} = Orders.create_order(order_attrs([{gin, 2}], %{payer_phone: unique_phone()}))
      {:ok, _} = Orders.mark_paid(o.id, "RCPT0001")
      {:ok, _} = Orders.claim(o.id, "Amina", "0001", "12:00")
      {:ok, _} = Orders.deliver(o.id)
      {:ok, conn: as(conn, user!(:admin)), gin: gin, cold: cold, low: low}
    end

    test "shows revenue, top drinks, waiters, service speed and the watch lists", %{conn: conn} do
      {:ok, view, html} = live(conn, "/staff/insights")
      assert html =~ "KES 2,000"
      assert html =~ "Top drinks"
      assert html =~ "Gin"
      assert html =~ "Amina"
      assert html =~ "Typical time to deliver"
      assert html =~ "Nearly Out"
      assert html =~ "Cold Seller"
      assert html =~ "Paid orders only, in Nairobi time"

      # range buttons switch the figures without a reload
      html = view |> element("button", "Today") |> render_click()
      assert html =~ "KES 2,000"
      assert html =~ ~s(aria-pressed="true")
    end

    test "charts are inline SVG with accessible labels, and no inline styles (strict CSP)", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, "/staff/insights")
      assert html =~ ~s(role="img" aria-label="Revenue per day")
      assert html =~ ~s(aria-label="Orders by hour of day")
      refute html =~ ~r/\sstyle="/
    end

    test "unpaid and cancelled orders never count as revenue", %{conn: conn, gin: gin} do
      {:ok, _} = Orders.create_order(order_attrs([{gin, 5}], %{payer_phone: unique_phone()}))
      {:ok, view, _} = live(conn, "/staff/insights")
      html = render(view)
      assert html =~ "KES 2,000"
      refute html =~ "KES 7,000"
      assert html =~ "Waiting to pay"
    end
  end

  describe "staff can add menu items (and a new category)" do
    setup %{conn: conn} do
      cat = category("Spirits", [product(%{name: "Existing"})])
      {:ok, conn: as(conn, user!(:staff)), cat: cat}
    end

    test "into an existing category", %{conn: conn, cat: cat} do
      {:ok, view, _} = live(conn, "/staff/menu")

      view
      |> form("form.pform", %{
        "name" => "Vodka",
        "price" => "1200",
        "category" => cat.id,
        "stock" => "6"
      })
      |> render_submit()

      assert Enum.any?(Catalog.menu(), fn c ->
               c.name == "Spirits" and
                 Enum.any?(c.products, &(&1.name == "Vodka" and &1.price_cents == 120_000))
             end)
    end

    test "into a brand-new category typed in the box, which appears on the menu", %{conn: conn} do
      {:ok, view, _} = live(conn, "/staff/menu")

      view
      |> form("form.pform", %{
        "name" => "Tusker",
        "price" => "300",
        "category" => "",
        "new_category" => "Beers",
        "stock" => ""
      })
      |> render_submit()

      beers = Enum.find(Catalog.menu(), &(&1.name == "Beers"))
      assert [%{name: "Tusker", price_cents: 30_000}] = beers.products
      assert build_conn() |> get("/") |> html_response(200) =~ "Beers"

      # typing the same category again reuses it rather than duplicating it
      view
      |> form("form.pform", %{
        "name" => "Guinness",
        "price" => "350",
        "category" => "",
        "new_category" => " beers ",
        "stock" => ""
      })
      |> render_submit()

      assert Repo.aggregate(from(c in Catalog.Category, where: c.slug == "beers"), :count) == 1
    end

    test "a category is required, and a bad price is explained", %{conn: conn} do
      {:ok, view, _} = live(conn, "/staff/menu")

      html =
        view
        |> form("form.pform", %{
          "name" => "Mystery",
          "price" => "100",
          "category" => "",
          "new_category" => "",
          "stock" => ""
        })
        |> render_submit()

      assert html =~ "Pick a category or type a new one."

      html =
        view
        |> form("form.pform", %{
          "name" => "Mystery",
          "price" => "abc",
          "category" => "",
          "new_category" => "Misc",
          "stock" => ""
        })
        |> render_submit()

      assert html =~ "Price"
    end
  end
end
