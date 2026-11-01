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
          |> Phoenix.Component.assign(
            staff: user,
            admin: Staff.admin?(user),
            paused: TheGame.Settings.ordering_paused?()
          )
          |> Phoenix.LiveView.attach_hook(:staff_pause, :handle_event, &pause_event/3)
          |> Phoenix.LiveView.attach_hook(:staff_menu_sync, :handle_info, &menu_sync/2)

        {:cont, socket}

      _ ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/staff/login")}
    end
  end

  # Role gate for a whole group of pages: `on_mount: {StaffAuth, {:area, :floor}}`.
  # Waiters get the board only; floor staff the floor pages; managers everything.
  def on_mount({:area, area}, _params, _session, socket) do
    if Staff.allowed?(socket.assigns.staff, area) do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.push_navigate(socket, to: "/staff")}
    end
  end

  # Pausing ordering is a floor/manager decision: refused for waiters even if the button is forged.
  defp pause_event("toggle_pause", _, socket) do
    if Staff.allowed?(socket.assigns.staff, :floor) do
      TheGame.Settings.pause_ordering(!TheGame.Settings.ordering_paused?())
      {:halt, Phoenix.Component.assign(socket, paused: TheGame.Settings.ordering_paused?())}
    else
      {:halt, socket}
    end
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
