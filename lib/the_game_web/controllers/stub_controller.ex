defmodule TheGameWeb.StubController do
  # Temporary until Phase 5 lands.
  use TheGameWeb, :controller
  def orders(conn, _), do: text(conn, "orders: coming in phase 5")
end
