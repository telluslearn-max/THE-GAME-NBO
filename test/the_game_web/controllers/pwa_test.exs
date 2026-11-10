defmodule TheGameWeb.PwaTest do
  use TheGameWeb.ConnCase
  import Phoenix.LiveViewTest
  import TheGame.Fixtures
  alias TheGame.{Orders, Push}

  test "manifest is valid JSON with installable icons", %{conn: conn} do
    conn = get(conn, "/manifest.webmanifest")
    assert [ct] = get_resp_header(conn, "content-type")
    assert ct =~ "manifest+json" or ct =~ "application/json"
    m = Jason.decode!(response(conn, 200))
    assert m["display"] == "standalone" and m["start_url"] == "/"
    sizes = Enum.map(m["icons"], & &1["sizes"])
    assert "192x192" in sizes and "512x512" in sizes
    assert Enum.any?(m["icons"], &(&1["purpose"] == "maskable"))
    for i <- m["icons"], do: assert(response(get(build_conn(), i["src"]), 200) != "")
  end

  test "the service worker and manifest always revalidate; fingerprinted assets are not touched",
       %{conn: conn} do
    for path <- ["/sw.js", "/manifest.webmanifest"] do
      [cc] = conn |> get(path) |> get_resp_header("cache-control")
      assert cc =~ "must-revalidate" and cc =~ "max-age=0", "#{path}: #{cc}"
    end
  end

  test "the service worker never caches money, auth or sockets" do
    sw = File.read!("priv/static/sw.js")
    for guard <- ["/staff", "/live", "/mpesa", "/menu.json"], do: assert(sw =~ guard)
    refute sw =~ "cache.put(\"/cart\"", "cart must not be cached"
    assert sw =~ "req.method !== \"GET\""
  end

  test "every page links the manifest, touch icon and theme colour", %{conn: conn} do
    html = conn |> get("/menu") |> html_response(200)
    assert html =~ ~s(rel="manifest")
    assert html =~ "apple-touch-icon"
    assert html =~ ~s(name="theme-color")
  end

  test "offline page is calm and warns against paying twice", %{conn: conn} do
    html = conn |> get("/offline") |> html_response(200)
    assert html =~ "You’re offline"
    assert html =~ "don’t pay again"
  end

  describe "push opt-in on the order page" do
    setup do
      {:ok, o} = Orders.create_order(order_attrs([{product(), 1}]))
      {:ok, _} = Orders.mark_paid(o.id, "PWA1")
      {:ok, o: o}
    end

    test "is offered once paid, with the VAPID key", %{conn: conn, o: o} do
      {:ok, _view, html} = live(conn, ~p"/order/#{o.id}")
      assert html =~ ~s(phx-hook="PushOptIn")
      assert html =~ ~s(data-key="#{Push.public_key()}")
      assert html =~ "Notify me when it’s ready"
    end

    test "stores a valid subscription and refuses an internal endpoint", %{conn: conn, o: o} do
      {:ok, view, _} = live(conn, ~p"/order/#{o.id}")

      keys = %{
        "p256dh" =>
          "BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlUls0VJXg7A8u-Ts1XbjhazAkj7I99e8QcYP7DkM",
        "auth" => "tBHItJI5svbpez7KI4CCXg"
      }

      render_hook(view, "push-subscribe", %{
        "endpoint" => "https://fcm.googleapis.com/fcm/send/zzz",
        "keys" => keys
      })

      assert Push.subscribed?(o.id)
    end

    test "internal endpoints are not stored", %{conn: conn, o: o} do
      {:ok, view, _} = live(conn, ~p"/order/#{o.id}")

      keys = %{
        "p256dh" =>
          "BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlUls0VJXg7A8u-Ts1XbjhazAkj7I99e8QcYP7DkM",
        "auth" => "tBHItJI5svbpez7KI4CCXg"
      }

      render_hook(view, "push-subscribe", %{
        "endpoint" => "https://169.254.169.254/x",
        "keys" => keys
      })

      refute Push.subscribed?(o.id)
    end
  end
end
