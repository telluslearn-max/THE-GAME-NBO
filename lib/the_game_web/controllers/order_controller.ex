defmodule TheGameWeb.OrderController do
  use TheGameWeb, :controller
  alias TheGame.Orders

  # Phase 3 stand-in: a static ticket. Phase 5 replaces this with a live LiveView.
  def show(conn, %{"id" => id}) do
    case Orders.get_order(id) do
      nil ->
        conn |> put_status(404) |> text("Order not found")

      order ->
        render(conn, :show, order: order, page_title: "Order #{order.pickup_code} — THE GAME")
    end
  end
end
