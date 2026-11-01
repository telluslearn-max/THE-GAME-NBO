defmodule TheGameWeb.MenuController do
  use TheGameWeb, :controller
  alias TheGame.{Catalog, Settings}

  def index(conn, _params) do
    render(conn, :index,
      categories: Catalog.menu(),
      paused: Settings.ordering_paused?(),
      page_title: "THE GAME — order and collect"
    )
  end

  @doc """
  Compact price/stock feed for the cart: `{"paused":false,"p":{"<id>":[price_cents,in_stock]}}`.
  Revalidated with an ETag so an unchanged menu costs a ~200-byte 304.
  """
  def feed(conn, _params) do
    p =
      for c <- Catalog.menu(), pr <- c.products, into: %{} do
        {pr.id, [pr.price_cents, if(pr.in_stock, do: 1, else: 0)]}
      end

    body = Jason.encode!(%{paused: Settings.ordering_paused?(), p: p})
    etag = ~s("#{Base.url_encode64(:crypto.hash(:md5, body), padding: false)}")

    conn = conn |> put_resp_header("etag", etag) |> put_resp_header("cache-control", "no-cache")

    if etag in get_req_header(conn, "if-none-match") do
      send_resp(conn, 304, "")
    else
      conn |> put_resp_content_type("application/json") |> send_resp(200, body)
    end
  end
end
