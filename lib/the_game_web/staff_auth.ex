defmodule TheGameWeb.StaffAuth do
  @moduledoc "Session plug and LiveView on_mount guard for everything under /staff."
  import Plug.Conn
  import Phoenix.Controller
  alias TheGame.Staff

  # Plug: dead views
  def require_staff(conn, _opts) do
    with id when is_binary(id) <- get_session(conn, :staff_id),
         %{} = user <- Staff.get_user(id) do
      assign(conn, :staff, user)
    else
      _ -> conn |> redirect(to: "/staff/login") |> halt()
    end
  end

  def log_in(conn, user) do
    conn |> configure_session(renew: true) |> put_session(:staff_id, user.id)
  end

  def log_out(conn), do: configure_session(conn, drop: true)

  # LiveView: re-checked on every (re)connect, so a deactivated account is cut off.
  def on_mount(:ensure_staff, _params, session, socket) do
    case session["staff_id"] && Staff.get_user(session["staff_id"]) do
      %{} = user ->
        TheGame.Catalog.subscribe()

        socket =
          socket
          |> Phoenix.Component.assign(staff: user, paused: TheGame.Settings.ordering_paused?())
          |> Phoenix.LiveView.attach_hook(:staff_pause, :handle_event, &pause_event/3)
          |> Phoenix.LiveView.attach_hook(:staff_menu_sync, :handle_info, &menu_sync/2)

        {:cont, socket}

      _ ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/staff/login")}
    end
  end

  defp pause_event("toggle_pause", _, socket) do
    TheGame.Settings.pause_ordering(!TheGame.Settings.ordering_paused?())
    {:halt, Phoenix.Component.assign(socket, paused: TheGame.Settings.ordering_paused?())}
  end

  defp pause_event(_, _, socket), do: {:cont, socket}

  defp menu_sync(:menu_changed, socket) do
    {:cont, Phoenix.Component.assign(socket, paused: TheGame.Settings.ordering_paused?())}
  end

  defp menu_sync(_, socket), do: {:cont, socket}

  @doc "Throttle key for a request: the client address, honouring one trusted proxy hop if configured."
  def client_key(conn) do
    if Application.get_env(:the_game, :trust_proxy, false) do
      case get_req_header(conn, "x-forwarded-for") do
        [v | _] -> v |> String.split(",") |> List.last() |> String.trim()
        _ -> ip(conn)
      end
    else
      ip(conn)
    end
  end

  defp ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
