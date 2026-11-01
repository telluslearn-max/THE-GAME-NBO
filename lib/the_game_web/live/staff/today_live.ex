defmodule TheGameWeb.Staff.TodayLive do
  @moduledoc "Today's takings (EAT calendar day) and what sold."
  use TheGameWeb, :live_view
  import TheGameWeb.StaffComponents
  alias TheGame.{Catalog, Orders, Payments}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Orders.subscribe_staff()
    {:ok, socket |> assign(page_title: "Today — THE GAME staff") |> load()}
  end

  @impl true
  def handle_info({:order_updated, _}, socket), do: {:noreply, load(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  defp load(socket),
    do: assign(socket, s: Orders.today_summary(), reviews: length(Payments.list_reviews()))

  @impl true
  def render(assigns) do
    ~H"""
    <.header active={:today} paused={@paused} reviews={@reviews} />
    <main id="main" class="wrap swide">
      <h1 class="h1">Today</h1>
      <div class="stats">
        <div>
          <span class="k">Taken</span><span class="v mono">{Catalog.money(@s.revenue_cents)}</span>
        </div>
        <div><span class="k">Orders</span><span class="v mono">{@s.orders}</span></div>
        <div><span class="k">Open now</span><span class="v mono">{@s.open}</span></div>
      </div>
      <p class="help">
        Counts paid orders since midnight EAT. Orders held for payment review are not included until honoured.
      </p>

      <h2 class="sh">What sold</h2>
      <p :if={@s.by_product == []} class="none">No sales yet today.</p>
      <ul class="rows">
        <li :for={p <- @s.by_product} class="row">
          <div>
            <span class="name">{p.name}</span><span class="price">{Catalog.money(p.cents)}</span>
          </div>
          <div class="act"><span class="mono big">{p.qty}</span></div>
        </li>
      </ul>
    </main>
    """
  end
end
