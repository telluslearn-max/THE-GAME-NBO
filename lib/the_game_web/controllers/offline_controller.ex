defmodule TheGameWeb.OfflineController do
  use TheGameWeb, :controller

  @doc "Shown by the service worker when a page needs the network and there is none."
  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-cache")
    |> render(:show, page_title: "Offline — THE GAME")
  end
end
