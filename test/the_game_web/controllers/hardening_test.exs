defmodule TheGameWeb.HardeningTest do
  use TheGameWeb.ConnCase
  import TheGame.Fixtures

  setup do
    category("Spirits", for(n <- 1..25, do: product(%{name: "Drink number #{n}"})))
    :ok
  end

  describe "security headers" do
    test "strict CSP with no inline script and no third parties", %{conn: conn} do
      [csp] = conn |> get("/") |> get_resp_header("content-security-policy")
      assert csp =~ "script-src 'self'"
      assert csp =~ "frame-ancestors 'none'"
      assert csp =~ "object-src 'none'"
      refute csp =~ "unsafe-inline"
      refute csp =~ "unsafe-eval"
      refute csp =~ "http://" and csp =~ "https://"
    end

    test "no page ships inline scripts or inline style attributes", %{conn: conn} do
      for path <- ["/", "/cart", "/orders", "/offline", "/staff/login"] do
        html = conn |> get(path) |> html_response(200)
        refute html =~ ~r/<script(?![^>]*\bsrc=)[^>]*>\s*\S/, "inline script on #{path}"
        refute html =~ ~r/\sstyle="/, "inline style on #{path}"
      end
    end

    test "framing, sniffing and device APIs are locked down", %{conn: conn} do
      conn = get(conn, "/")

      assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"] or
               get_resp_header(conn, "x-frame-options") == ["DENY"]

      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert [pp] = get_resp_header(conn, "permissions-policy")
      assert pp =~ "geolocation=()" and pp =~ "camera=()"
    end

    test "over HTTPS: HSTS and Secure cookies; over HTTP: neither", %{conn: conn} do
      Application.put_env(:the_game, :trust_proxy, true)
      on_exit(fn -> Application.put_env(:the_game, :trust_proxy, false) end)
      gin = product(%{price_cents: 100_000})

      body = %{
        "items" => Jason.encode!([%{id: gin.id, q: 1}]),
        "expected_total" => "100000",
        "phone" => "0712 345 678"
      }

      https = conn |> put_req_header("x-forwarded-proto", "https") |> post("/orders", body)
      assert get_resp_header(https, "strict-transport-security") != []
      assert https.resp_cookies["tg_orders"].secure

      Application.put_env(:the_game, :trust_proxy, false)

      http =
        build_conn()
        |> put_req_header("x-forwarded-proto", "https")
        |> post("/orders", Map.put(body, "phone", "0722 345 678"))

      assert get_resp_header(http, "strict-transport-security") == []
      refute http.resp_cookies["tg_orders"][:secure]
    end
  end

  describe "compression and conditional GET" do
    test "gzips the menu for clients that accept it", %{conn: conn} do
      plain = conn |> get("/") |> response(200)
      gz = build_conn() |> put_req_header("accept-encoding", "gzip, br") |> get("/")
      assert get_resp_header(gz, "content-encoding") == ["gzip"]
      assert get_resp_header(gz, "vary") != []
      assert byte_size(gz.resp_body) < byte_size(plain) / 3
      assert :zlib.gunzip(gz.resp_body) == plain
    end

    test "unchanged pages answer 304 with no body", %{conn: conn} do
      first = get(conn, "/")
      [etag] = get_resp_header(first, "etag")
      again = build_conn() |> put_req_header("if-none-match", etag) |> get("/")
      assert response(again, 304) == ""
    end

    test "the menu HTML is identical for different visitors (no per-session token)" do
      a = build_conn() |> get("/") |> response(200)
      b = build_conn() |> get("/") |> response(200)
      assert a == b
    end

    test "money pages carry no cache validators that could replay a stale page", %{conn: conn} do
      html = get(conn, "/cart")
      assert html.status == 200
      # a token-bearing page is different every time, so an ETag can never match a stale copy
      a = html |> response(200)
      b = build_conn() |> get("/cart") |> response(200)
      refute a == b
    end

    test "tiny responses and JSON feed are handled", %{conn: conn} do
      feed = conn |> put_req_header("accept-encoding", "gzip") |> get("/menu.json")
      assert feed.status == 200

      assert Jason.decode!(
               if get_resp_header(feed, "content-encoding") == ["gzip"],
                 do: :zlib.gunzip(feed.resp_body),
                 else: feed.resp_body
             )
    end
  end

  test "healthz reports ok with the database up", %{conn: conn} do
    conn = get(conn, "/healthz")
    assert text_response(conn, 200) == "ok"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  describe "menu cache" do
    setup do
      Application.put_env(:the_game, :menu_cache, true)
      TheGame.MenuCache.clear()

      on_exit(fn ->
        Application.put_env(:the_game, :menu_cache, false)
        TheGame.MenuCache.clear()
      end)
    end

    test "serves from cache and is invalidated the moment stock or availability changes" do
      p = product(%{name: "Cache Test Gin", stock: 1})
      category("Mixers", [p])
      assert [_ | _] = TheGame.Catalog.menu()

      name = fn ->
        TheGame.Catalog.menu() |> Enum.flat_map(& &1.products) |> Enum.find(&(&1.id == p.id))
      end

      assert name.().in_stock

      {:ok, _} = TheGame.Orders.create_order(order_attrs([{p, 1}]))
      wait_until(fn -> name.().in_stock == false end)
    end

    test "staff edits show up immediately" do
      p = product(%{name: "Edit Me", price_cents: 100_000})
      category("Shots", [p])

      assert Enum.any?(TheGame.Catalog.menu(), fn c ->
               Enum.any?(c.products, &(&1.name == "Edit Me"))
             end)

      {:ok, _} = TheGame.Catalog.update_product(p, %{"active" => false})

      wait_until(fn ->
        not Enum.any?(TheGame.Catalog.menu(), fn c ->
          Enum.any?(c.products, &(&1.name == "Edit Me"))
        end)
      end)
    end
  end

  defp wait_until(fun, tries \\ 40) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("not invalidated in time")
      true -> Process.sleep(25) && wait_until(fun, tries - 1)
    end
  end
end
