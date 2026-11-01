defmodule TheGameWeb.StaffComponents do
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: TheGameWeb.Endpoint,
    router: TheGameWeb.Router,
    statics: TheGameWeb.static_paths()

  import Plug.CSRFProtection, only: [get_csrf_token: 0]

  attr :active, :atom, required: true
  attr :paused, :boolean, required: true
  attr :reviews, :integer, default: 0
  attr :admin, :boolean, default: false

  def header(assigns) do
    ~H"""
    <header class="wrap sbar">
      <div class="sbar-r1">
        <a class="brand" href={~p"/staff"} aria-label="THE GAME staff">
          <TheGameWeb.Layouts.wordmark />
        </a>
        <button
          type="button"
          class={["switch", @paused && "off"]}
          phx-click="toggle_pause"
          role="switch"
          aria-checked={to_string(!@paused)}
        >
          <span class="knob"></span>
          <span class="lbl">{if @paused, do: "Ordering paused", else: "Taking orders"}</span>
        </button>
      </div>
      <nav class="snav" aria-label="Staff">
        <a href={~p"/staff"} aria-current={@active == :board && "page"}>Board</a>
        <a href={~p"/staff/reviews"} aria-current={@active == :reviews && "page"}>
          Payments <span :if={@reviews > 0} class="count">{@reviews}</span>
        </a>
        <a href={~p"/staff/menu"} aria-current={@active == :menu && "page"}>Menu</a>
        <a href={~p"/staff/today"} aria-current={@active == :today && "page"}>Today</a>
        <a :if={@admin} href={~p"/staff/insights"} aria-current={@active == :insights && "page"}>
          Insights
        </a>
        <form method="post" action={~p"/staff/logout"} class="out">
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <button type="submit">Sign out</button>
        </form>
      </nav>
    </header>
    """
  end

  def age(nil), do: ""

  def age(%DateTime{} = dt) do
    m = div(DateTime.diff(DateTime.utc_now(), dt), 60)
    if m < 1, do: "just now", else: "#{m} min"
  end

  def eat(%DateTime{} = dt), do: dt |> DateTime.add(3 * 3600) |> Calendar.strftime("%H:%M")
end
