defmodule TheGameWeb.CheckoutTest do
  use TheGameWeb.ConnCase
  import TheGame.Fixtures
  alias TheGame.{Orders, Settings}

  setup do
    {:ok, gin: product(%{name: "Gin", price_cents: 125_000, stock: 4})}
  end

  defp items(p, q), do: Jason.encode!([%{id: p.id, q: q}])

  defp checkout(conn, p, q, extra \\ %{}) do
    params =
      Map.merge(
        %{
          "items" => items(p, q),
          "expected_total" => "#{p.price_cents * q}",
          "phone" => "0712 345 678"
        },
        extra
      )

    post(conn, ~p"/orders", params)
  end

  test "cart page renders the shell and loads only the cart script", %{conn: conn} do
    html = conn |> get(~p"/cart") |> html_response(200)
    assert html =~ ~s(id="cart-form")
    assert html =~ ~r|<script[^>]*src="/assets/js/cart[^"]*\.js|
    refute conn |> get(~p"/menu") |> html_response(200) =~ "/assets/js/cart"
    assert html =~ ~s(name="_csrf_token")
  end

  test "successful checkout creates the order, remembers it in a signed cookie, redirects", %{
    conn: conn,
    gin: gin
  } do
    conn = checkout(conn, gin, 2)
    assert %{id: id} = order_id_from(conn)
    assert redirected_to(conn) == "/order/#{id}?new=1"
    assert conn.resp_cookies["tg_orders"].value =~ "."
    assert conn.resp_cookies["tg_orders"].http_only
    order = Orders.get_order!(id)
    assert order.total_cents == 250_000
    assert order.status == :pending_payment
  end

  test "stale total is rejected with the new total and nothing is reserved", %{
    conn: conn,
    gin: gin
  } do
    conn = checkout(conn, gin, 1, %{"expected_total" => "100000"})
    assert html_response(conn, 422) =~ "Prices changed. The new total is KES 1,250"
    assert TheGame.Repo.reload!(gin).stock == 4
  end

  test "sold out items are named", %{conn: conn, gin: gin} do
    assert checkout(conn, gin, 5) |> html_response(422) =~ "Sold out right now: Gin"
  end

  test "bad phone, empty cart, junk payload", %{conn: conn, gin: gin} do
    assert checkout(conn, gin, 1, %{"phone" => "123"}) |> html_response(422) =~
             "Enter the M-Pesa number"

    assert post(conn, ~p"/orders", %{"items" => "[]", "phone" => "0712345678"})
           |> html_response(422) =~ "cart is empty"

    assert post(conn, ~p"/orders", %{"items" => "not json", "phone" => "0712345678"})
           |> html_response(422) =~ "couldn’t read your cart"

    assert post(conn, ~p"/orders", %{}) |> html_response(422) =~ "couldn’t read your cart"
  end

  test "ordering paused is explained", %{conn: conn, gin: gin} do
    Settings.pause_ordering(true)
    assert checkout(conn, gin, 1) |> html_response(422) =~ "Ordering is paused"
  end

  test "double submit returns the visitor to their own unpaid order", %{conn: conn, gin: gin} do
    first = checkout(conn, gin, 1)
    %{id: id} = order_id_from(first)

    # same browser (cookie replayed), same phone
    again = recycle_with_cookies(conn, first) |> checkout(gin, 1)
    assert redirected_to(again) == "/order/#{id}"
  end

  test "a stranger typing someone's number never learns the order id", %{conn: conn, gin: gin} do
    %{id: id} = conn |> checkout(gin, 1) |> order_id_from()
    stranger = build_conn() |> checkout(gin, 1)
    html = html_response(stranger, 422)
    assert html =~ "already has an unpaid order"
    refute html =~ id
  end

  test "menu.json is compact and revalidates with an etag", %{conn: conn, gin: gin} do
    category("Spirits", [gin])
    c1 = get(conn, "/menu.json")
    assert %{"paused" => false, "p" => %{} = p} = json_response(c1, 200)
    assert p[gin.id] == [125_000, 1]
    [etag] = get_resp_header(c1, "etag")
    c2 = conn |> put_req_header("if-none-match", etag) |> get("/menu.json")
    assert response(c2, 304) == ""
  end

  defp recycle_with_cookies(_conn, prev) do
    Enum.reduce(prev.resp_cookies, Phoenix.ConnTest.recycle(prev), fn {k, %{value: v}}, c ->
      put_req_header(c, "cookie", "#{k}=#{v}")
    end)
  end

  defp order_id_from(conn) do
    [_, id] = Regex.run(~r|/order/([0-9a-f-]{36})|, redirected_to(conn))
    %{id: id}
  end

  describe "unpaid-order check as the number is typed" do
    test "a number with no unpaid order is not blocked", %{conn: conn} do
      assert %{"blocked" => false, "order" => nil} =
               conn |> get("/cart/check", %{"phone" => "0711 222 333"}) |> json_response(200)
    end

    test "junk numbers are simply not blocked", %{conn: conn} do
      for bad <- ["", "123", "abc", "0612345678"] do
        assert %{"blocked" => false} =
                 conn |> get("/cart/check", %{"phone" => bad}) |> json_response(200)
      end
    end

    test "the owner of the unpaid order is told, with a link to it", %{conn: conn, gin: gin} do
      first = checkout(conn, gin, 1)
      %{id: id} = order_id_from(first)

      body =
        recycle_with_cookies(conn, first)
        |> get("/cart/check", %{"phone" => "0712 345 678"})
        |> json_response(200)

      assert %{"blocked" => true, "order" => link} = body
      assert link == "/order/#{id}"
    end

    test "anyone else is only told 'blocked', never the order's address", %{conn: conn, gin: gin} do
      first = checkout(conn, gin, 1)
      %{id: id} = order_id_from(first)

      res = build_conn() |> get("/cart/check", %{"phone" => "0712345678"})
      assert %{"blocked" => true, "order" => nil} = json_response(res, 200)
      refute res.resp_body =~ id
      assert get_resp_header(res, "cache-control") == ["no-store"]
    end

    test "after cancelling, the number is free again", %{conn: conn, gin: gin} do
      first = checkout(conn, gin, 1)
      Orders.cancel(order_id_from(first).id)

      assert %{"blocked" => false} =
               build_conn()
               |> get("/cart/check", %{"phone" => "0712345678"})
               |> json_response(200)
    end

    test "the cart page offers the blocked message and a plain 'Place order' button", %{
      conn: conn
    } do
      html = conn |> get(~p"/cart") |> html_response(200)
      assert html =~ ~s(id="blocked")
      assert html =~ "This number has an unpaid order."
      assert html =~ "don’t pay again"
      assert html =~ "Place order"
      refute html =~ "3308963"
      refute html =~ "111222"
    end
  end
end
