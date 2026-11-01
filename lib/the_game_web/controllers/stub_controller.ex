defmodule TheGameWeb.StubController do
  # Temporary until Phase 3 / 5 land.
  use TheGameWeb, :controller
  def cart(conn, _), do: text(conn, "cart: coming in phase 3")
  def orders(conn, _), do: text(conn, "orders: coming in phase 5")
end
