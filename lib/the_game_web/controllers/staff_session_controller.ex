defmodule TheGameWeb.StaffSessionController do
  use TheGameWeb, :controller
  alias TheGame.Staff
  alias TheGameWeb.StaffAuth

  def new(conn, _), do: render_form(conn, nil)

  def create(conn, %{"email" => email, "password" => password}) do
    case Staff.authenticate(email, password, StaffAuth.client_key(conn)) do
      {:ok, user} ->
        conn
        |> StaffAuth.log_in(user)
        |> redirect(to: if(Staff.admin?(user), do: "/staff/insights", else: "/staff"))

      {:error, :rate_limited} ->
        conn
        |> put_status(429)
        |> render_form("Too many attempts. Wait 10 minutes and try again.")

      {:error, :invalid} ->
        conn |> put_status(401) |> render_form("Wrong email or password.")
    end
  end

  def create(conn, _), do: conn |> put_status(401) |> render_form("Wrong email or password.")

  def delete(conn, _), do: conn |> StaffAuth.log_out() |> redirect(to: "/staff/login")

  defp render_form(conn, error) do
    conn |> assign(:noindex, true) |> render(:new, error: error, page_title: "Staff — THE GAME")
  end
end
