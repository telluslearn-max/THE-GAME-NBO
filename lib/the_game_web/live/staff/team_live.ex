defmodule TheGameWeb.Staff.TeamLive do
  @moduledoc """
  The manager's people page: add someone, give them a role, change it later, reset a password,
  switch an account off. Managers only (enforced when the page mounts). A change takes effect the
  next time that person opens a page.
  """
  use TheGameWeb, :live_view
  import TheGameWeb.StaffComponents
  alias TheGame.{Payments, Staff}
  alias TheGame.Staff.User

  @roles [admin: "Manager", staff: "Floor staff", waiter: "Waiter"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Team — THE GAME admin",
       roles: @roles,
       msg: nil,
       error: nil,
       reviews: length(Payments.list_reviews())
     )
     |> load()}
  end

  defp load(socket), do: assign(socket, users: Staff.list_users())

  @impl true
  def handle_event(
        "add",
        %{"name" => name, "email" => email, "role" => role, "password" => pw},
        socket
      ) do
    case role_atom(role) &&
           Staff.create_user(%{name: name, email: email, password: pw, role: role_atom(role)}) do
      {:ok, u} ->
        {:noreply, socket |> note("#{u.email} added as #{Staff.role_label(u.role)}.") |> load()}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, fail(socket, first_error(cs))}

      _ ->
        {:noreply, fail(socket, "Pick a role.")}
    end
  end

  def handle_event("role", %{"uid" => id, "role" => role}, socket) do
    with {:ok, user} <- fetch(id),
         r when not is_nil(r) <- role_atom(role),
         {:ok, u} <- Staff.update_role(user.id, r) do
      {:noreply, socket |> note("#{u.email} is now #{Staff.role_label(u.role)}.") |> load()}
    else
      {:error, :last_admin} ->
        {:noreply, socket |> fail("There must always be one active manager.") |> load()}

      _ ->
        {:noreply, socket |> fail("Couldn’t change that role.") |> load()}
    end
  end

  def handle_event("active", %{"uid" => id, "to" => to}, socket) do
    with {:ok, user} <- fetch(id),
         false <- user.id == socket.assigns.staff.id and to == "off",
         {:ok, u} <- Staff.set_active(user.id, to == "on") do
      {:noreply,
       socket
       |> note("#{u.email} #{if u.active, do: "switched on", else: "switched off"}.")
       |> load()}
    else
      true ->
        {:noreply, fail(socket, "You can’t switch off your own account.")}

      {:error, :last_admin} ->
        {:noreply, fail(socket, "There must always be one active manager.")}

      _ ->
        {:noreply, fail(socket, "Couldn’t change that account.")}
    end
  end

  def handle_event("reset", %{"uid" => id, "password" => pw}, socket) do
    with {:ok, user} <- fetch(id),
         {:ok, u} <- Staff.reset_password(user.id, pw) do
      {:noreply, socket |> note("New password set for #{u.email}.") |> load()}
    else
      {:error, %Ecto.Changeset{} = cs} -> {:noreply, fail(socket, first_error(cs))}
      _ -> {:noreply, fail(socket, "Couldn’t set that password.")}
    end
  end

  defp fetch(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %User{} = u <- TheGame.Repo.get(User, uuid) do
      {:ok, u}
    else
      _ -> :error
    end
  end

  defp role_atom(r), do: Enum.find_value(Keyword.keys(@roles), &(Atom.to_string(&1) == r && &1))
  defp note(socket, m), do: assign(socket, msg: m, error: nil)
  defp fail(socket, m), do: assign(socket, error: m, msg: nil)

  defp first_error(cs) do
    case cs.errors do
      [{field, {msg, _}} | _] -> "#{Phoenix.Naming.humanize(field)} #{msg}"
      _ -> "Couldn’t save."
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header role={@staff.role} active={:team} paused={@paused} reviews={@reviews} />
    <main id="main" class="wrap swide">
      <h1 class="h1">Team</h1>
      <p :if={@msg} class="notice ok" role="status">{@msg}</p>
      <p :if={@error} class="notice" role="alert">{@error}</p>

      <dl class="rolekey">
        <div>
          <dt>Manager</dt>
          <dd>Everything: Insights, Team, menu, payments.</dd>
        </div>
        <div>
          <dt>Floor staff</dt>
          <dd>The board, payments, menu and today. What everyone has now.</dd>
        </div>
        <div>
          <dt>Waiter</dt>
          <dd>The board only: take an order, confirm, deliver.</dd>
        </div>
      </dl>

      <details class="newp">
        <summary>Add a person</summary>
        <form phx-submit="add" class="pform tform">
          <input
            class="text"
            name="name"
            placeholder="Name"
            maxlength="40"
            autocomplete="off"
            required
          />
          <input
            class="text"
            name="email"
            type="email"
            placeholder="Email (their login)"
            autocomplete="off"
            required
          />
          <select class="text" name="role" aria-label="Role">
            <option :for={{r, label} <- @roles} value={r} selected={r == :waiter}>{label}</option>
          </select>
          <input
            class="text"
            name="password"
            type="text"
            placeholder="Password (8+ characters)"
            autocomplete="off"
            required
          />
          <button class="sbtn go" type="submit">Add</button>
        </form>
      </details>

      <ul class="plist">
        <li :for={u <- @users} id={"u-" <> u.id} class={[!u.active && "off"]}>
          <div class="urow">
            <span class="pname">
              {if u.name != "", do: u.name, else: u.email}
              <small :if={u.id == @staff.id} class="you">you</small>
            </span>
            <span class="uemail">{u.email}</span>

            <form phx-change="role" class="uf">
              <input type="hidden" name="uid" value={u.id} />
              <label class="sr" for={"role-" <> u.id}>Role for {u.email}</label>
              <select id={"role-" <> u.id} class="text" name="role">
                <option :for={{r, label} <- @roles} value={r} selected={r == u.role}>{label}</option>
              </select>
            </form>

            <button
              :if={u.id != @staff.id}
              class="sbtn"
              phx-click="active"
              phx-value-uid={u.id}
              phx-value-to={if u.active, do: "off", else: "on"}
            >
              {if u.active, do: "Switch off", else: "Switch on"}
            </button>
          </div>
          <details class="pw">
            <summary>Set a new password</summary>
            <form phx-submit="reset" class="uf pwf">
              <input type="hidden" name="uid" value={u.id} />
              <label class="sr" for={"pw-" <> u.id}>New password for {u.email}</label>
              <input
                id={"pw-" <> u.id}
                class="text"
                name="password"
                type="text"
                placeholder="New password (8+ characters)"
                autocomplete="off"
              />
              <button class="sbtn" type="submit">Save</button>
            </form>
          </details>
        </li>
      </ul>
    </main>
    """
  end
end
