defmodule TheGameWeb.OrdersController do
  use TheGameWeb, :controller
  alias TheGame.Orders
  alias TheGameWeb.History

  @doc "The visitor's own orders (from their signed cookie), newest first."
  def index(conn, _params) do
    orders = conn |> History.ids() |> Orders.list_by_ids()
    render(conn, :index, orders: orders, page_title: "Your orders — THE GAME")
  end
end
