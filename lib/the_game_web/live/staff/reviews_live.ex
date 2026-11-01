defmodule TheGameWeb.Staff.ReviewsLive do
  @moduledoc "Money that did not cleanly settle an order. Nothing here is automatic: a person decides."
  use TheGameWeb, :live_view
  import TheGameWeb.StaffComponents
  alias TheGame.{Catalog, Orders, Payments}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Orders.subscribe_staff()

    {:ok,
     socket |> assign(page_title: "Payments — THE GAME staff", confirm: nil, error: nil) |> load()}
  end

  @impl true
  def handle_info({:order_updated, _}, socket), do: {:noreply, load(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("ask", %{"id" => id, "do" => action}, socket),
    do: {:noreply, assign(socket, confirm: {id, action})}

  def handle_event("back", _, socket), do: {:noreply, assign(socket, confirm: nil)}

  def handle_event("resolve", %{"id" => id, "do" => action}, socket) do
    resolution = %{"honor" => :honored, "refund" => :refunded}[action]

    error =
      case resolution && Payments.resolve_review(id, resolution) do
        {:ok, _} -> nil
        {:error, :already_resolved} -> "Someone already resolved that one."
        _ -> "Couldn’t resolve it. Refresh and try again."
      end

    {:noreply, socket |> assign(confirm: nil, error: error) |> load()}
  end

  defp load(socket), do: assign(socket, reviews: Payments.list_reviews())

  defp kind_text(:late), do: "Paid after the order expired or was cancelled"
  defp kind_text(:short), do: "Paid less than the total"
  defp kind_text(:extra), do: "Extra payment (double or overpaid)"
  defp kind_text(:unmatched), do: "Payment we could not match"

  @impl true
  def render(assigns) do
    ~H"""
    <.header active={:reviews} paused={@paused} reviews={length(@reviews)} bookings={@new_bookings} />
    <main id="main" class="wrap swide">
      <h1 class="h1">Payments to check</h1>
      <p :if={@error} class="notice" role="alert">{@error}</p>
      <p :if={@reviews == []} class="none">All clear. Every payment is matched to an order.</p>

      <article :for={r <- @reviews} class="scard warn" id={"r-" <> r.id}>
        <div class="scard-h">
          <span class="scode">{r.order && r.order.pickup_code}</span>
          <span class="sage">{r.kind}</span>
        </div>
        <p class="p">{kind_text(r.kind)}</p>
        <dl class="kv">
          <div>
            <dt>Paid</dt>
            <dd class="mono">{Catalog.money(r.amount_cents)}</dd>
          </div>
          <div :if={r.order}>
            <dt>Order total</dt>
            <dd class="mono">{Catalog.money(r.order.total_cents)}</dd>
          </div>
          <div>
            <dt>M-Pesa receipt</dt>
            <dd class="mono">{r.mpesa_receipt}</dd>
          </div>
          <div>
            <dt>Number</dt>
            <dd class="mono">{r.phone}</dd>
          </div>
          <div :if={r.order}>
            <dt>Order status</dt>
            <dd>{r.order.status}</dd>
          </div>
        </dl>
        <p class="help">{r.note}</p>

        <div :if={@confirm == nil or elem(@confirm, 0) != r.id} class="sact">
          <button
            :if={r.order && r.order.status == :flagged}
            class="sbtn go"
            phx-click="ask"
            phx-value-id={r.id}
            phx-value-do="honor"
          >
            Honour: send to bar
          </button>
          <button class="sbtn" phx-click="ask" phx-value-id={r.id} phx-value-do="refund">
            Refunded / dismiss
          </button>
        </div>
        <div :if={@confirm && elem(@confirm, 0) == r.id} class="sact">
          <p class="help full">
            {if elem(@confirm, 1) == "honor",
              do: "Accept this payment and send the order to the bar?",
              else:
                "Confirm you have refunded this customer in M-Pesa (or that nothing is owed). The order will be closed."}
          </p>
          <button
            class="sbtn go"
            phx-click="resolve"
            phx-value-id={r.id}
            phx-value-do={elem(@confirm, 1)}
            phx-disable-with="…"
          >
            Yes
          </button>
          <button class="sbtn" phx-click="back">Back</button>
        </div>
      </article>
    </main>
    """
  end
end
