defmodule TheGameWeb.Staff.InsightsLive do
  @moduledoc """
  The owner's overview. Admin logins only; read-only, so it cannot affect the bar's operations.
  Charts are plain inline SVG (no chart library, nothing extra to download).
  """
  use TheGameWeb, :live_view
  import TheGameWeb.StaffComponents
  alias TheGame.{Catalog, Insights, Payments}

  @ranges [today: "Today", week: "7 days", month: "30 days", all: "All time"]

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.admin do
      if connected?(socket), do: Process.send_after(self(), :tick, 60_000)

      {:ok,
       socket
       |> assign(
         page_title: "Insights — THE GAME admin",
         range: :week,
         reviews: length(Payments.list_reviews())
       )
       |> load()}
    else
      {:ok, push_navigate(socket, to: ~p"/staff")}
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 60_000)
    {:noreply, load(socket)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("range", %{"r" => r}, socket) do
    range = Enum.find(Keyword.keys(@ranges), &(Atom.to_string(&1) == r)) || :week
    {:noreply, socket |> assign(range: range) |> load()}
  end

  defp load(socket),
    do: assign(socket, s: Insights.summary(socket.assigns.range), ranges: @ranges)

  defp money(c), do: Catalog.money(c)
  defp mins(nil), do: "—"
  defp mins(m), do: "#{m} min"

  defp day_label(%Date{} = d), do: Calendar.strftime(d, "%d %b")

  defp hour_label(h), do: String.pad_leading(Integer.to_string(h), 2, "0")

  defp method_label("till"), do: "Paid at the till"
  defp method_label(_), do: "M-Pesa prompt"

  attr :data, :list, required: true
  attr :label, :string, required: true
  attr :every, :integer, default: 1

  # A column chart as inline SVG on a fixed 320x130 canvas, so bars and labels keep their
  # proportions however many bars there are. Sizes are SVG attributes (not CSS): strict-CSP safe.
  defp bars(assigns) do
    max = assigns.data |> Enum.map(& &1.value) |> Enum.max(fn -> 0 end) |> max(1)
    n = max(length(assigns.data), 1)
    slot = 320 / n
    assigns = assign(assigns, max: max, slot: slot, bw: Float.round(slot * 0.66, 1))

    ~H"""
    <svg class="bars" viewBox="0 0 320 130" role="img" aria-label={@label}>
      <line x1="0" y1="106" x2="320" y2="106" class="axis" />
      <g :for={{d, i} <- Enum.with_index(@data)}>
        <rect
          x={Float.round(i * @slot + (@slot - @bw) / 2, 1)}
          y={Float.round(106 - 96 * d.value / @max, 1)}
          width={@bw}
          height={Float.round(96 * d.value / @max, 1)}
          rx="1.5"
        >
          <title>{d.tip}</title>
        </rect>
        <text
          :if={rem(i, @every) == 0}
          x={Float.round(i * @slot + @slot / 2, 1)}
          y="122"
          text-anchor="middle"
        >
          {d.label}
        </text>
      </g>
    </svg>
    """
  end

  defp plural(1, word), do: "1 #{word}"
  defp plural(n, word), do: "#{n} #{word}s"

  @impl true
  def render(assigns) do
    ~H"""
    <.header admin={@admin} active={:insights} paused={@paused} reviews={@reviews} />
    <main id="main" class="wrap swide">
      <h1 class="h1">Insights</h1>

      <div class="rangebar" role="group" aria-label="Time range">
        <button
          :for={{r, text} <- @ranges}
          type="button"
          phx-click="range"
          phx-value-r={r}
          aria-pressed={to_string(@range == r)}
          class={["rbtn", @range == r && "on"]}
        >
          {text}
        </button>
      </div>
      <p class="help">Paid orders only, in Nairobi time. Refreshes every minute.</p>

      <div class="stats six">
        <div>
          <span class="k">Revenue</span><span class="v mono">{money(@s.kpi.revenue_cents)}</span>
        </div>
        <div><span class="k">Orders</span><span class="v mono">{@s.kpi.orders}</span></div>
        <div>
          <span class="k">Average order</span><span class="v mono">{money(@s.kpi.avg_order_cents)}</span>
        </div>
        <div><span class="k">Drinks sold</span><span class="v mono">{@s.kpi.units}</span></div>
        <div>
          <span class="k">Customers</span>
          <span class="v mono">{@s.kpi.customers}</span>
          <span class="sub">{@s.kpi.repeat_customers} came back</span>
        </div>
        <div>
          <span class="k">Orders paid</span>
          <span class="v mono">{@s.funnel.conversion_pct}%</span>
          <span class="sub">{@s.funnel.paid} of {@s.funnel.created} placed</span>
        </div>
      </div>

      <section class="isec">
        <h2 class="sh">Sales by day</h2>
        <.bars
          data={
            for d <- @s.by_day,
                do: %{
                  value: d.cents,
                  label: day_label(d.day),
                  tip: "#{day_label(d.day)}: #{money(d.cents)} (#{plural(d.orders, "order")})"
                }
          }
          label="Revenue per day"
          every={max(div(length(@s.by_day), 8), 1)}
        />
      </section>

      <section class="isec">
        <h2 class="sh">Busiest hours</h2>
        <.bars
          data={
            for h <- @s.by_hour,
                do: %{
                  value: h.orders,
                  label: hour_label(h.hour),
                  tip: "#{hour_label(h.hour)}:00: #{plural(h.orders, "order")}, #{money(h.cents)}"
                }
          }
          label="Orders by hour of day"
          every={3}
        />
      </section>

      <div class="igrid">
        <section class="isec">
          <h2 class="sh">Top drinks</h2>
          <p :if={@s.products == []} class="none">No sales in this range.</p>
          <ol class="rank">
            <li :for={p <- @s.products}>
              <span class="rn">{p.name}</span>
              <meter
                value={p.qty}
                min="0"
                max={hd(@s.products).qty}
                aria-label={"#{p.name}: #{p.qty} sold"}
              >
              </meter>
              <span class="rv mono">{p.qty} · {money(p.cents)}</span>
            </li>
          </ol>
        </section>

        <section class="isec">
          <h2 class="sh">How they paid</h2>
          <p :if={@s.methods == []} class="none">No sales in this range.</p>
          <dl class="srows">
            <div :for={m <- @s.methods}>
              <dt>{method_label(m.method)}</dt>
              <dd><b class="mono">{money(m.cents)}</b> · {plural(m.orders, "order")}</dd>
            </div>
          </dl>

          <h2 class="sh">Orders placed</h2>
          <dl class="srows">
            <div>
              <dt>Paid</dt>
              <dd><b class="mono">{@s.funnel.paid}</b></dd>
            </div>
            <div>
              <dt>Waiting to pay</dt>
              <dd><b class="mono">{@s.funnel.waiting}</b></dd>
            </div>
            <div>
              <dt>Expired unpaid</dt>
              <dd><b class="mono">{@s.funnel.expired}</b></dd>
            </div>
            <div>
              <dt>Cancelled</dt>
              <dd><b class="mono">{@s.funnel.cancelled}</b></dd>
            </div>
            <div :if={@s.funnel.flagged > 0}>
              <dt>Being checked</dt>
              <dd><b class="mono">{@s.funnel.flagged}</b></dd>
            </div>
          </dl>
        </section>

        <section class="isec">
          <h2 class="sh">Service speed</h2>
          <dl class="srows">
            <div>
              <dt>Typical time to deliver</dt>
              <dd><b class="mono">{mins(@s.speed.median_min)}</b></dd>
            </div>
            <div>
              <dt>Average</dt>
              <dd><b class="mono">{mins(@s.speed.avg_min)}</b></dd>
            </div>
            <div>
              <dt>Delivered</dt>
              <dd><b class="mono">{@s.speed.delivered}</b></dd>
            </div>
          </dl>
          <p class="help">From the moment an order is paid to the waiter tapping Delivered.</p>
        </section>

        <section class="isec">
          <h2 class="sh">Orders per waiter</h2>
          <p :if={@s.waiters == []} class="none">
            No orders were taken by a named waiter in this range.
          </p>
          <dl class="srows">
            <div :for={w <- @s.waiters}>
              <dt>{w.name}</dt>
              <dd>
                <b class="mono">{w.orders}</b> {if w.orders == 1, do: "order", else: "orders"} · {money(
                  w.cents
                )}
              </dd>
            </div>
          </dl>
        </section>

        <section class="isec">
          <h2 class="sh">Running low</h2>
          <p :if={@s.low_stock == []} class="none">Nothing is down to its last few.</p>
          <dl class="srows">
            <div :for={p <- @s.low_stock}>
              <dt>{p.name}</dt>
              <dd><b class={["mono", p.stock == 0 && "out"]}>{p.stock}</b> left</dd>
            </div>
          </dl>
        </section>

        <section class="isec">
          <h2 class="sh">Didn’t sell</h2>
          <p :if={@s.unsold == []} class="none">Every drink on the menu sold at least once.</p>
          <p :if={@s.unsold != []} class="help">On the menu, no sales in this range:</p>
          <p class="unsold">{Enum.join(@s.unsold, " · ")}</p>
        </section>
      </div>
    </main>
    """
  end
end
