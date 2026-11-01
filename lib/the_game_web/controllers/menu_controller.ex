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
end
