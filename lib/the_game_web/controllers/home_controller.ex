defmodule TheGameWeb.HomeController do
  use TheGameWeb, :controller

  @doc "The front face: what THE GAME is, how ordering works, and one big way in to the menu."
  def index(conn, _params) do
    render(conn, :index,
      paused: TheGame.Settings.ordering_paused?(),
      page_title: "THE GAME — order drinks from your table"
    )
  end
end
