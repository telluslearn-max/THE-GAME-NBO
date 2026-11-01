defmodule TheGameWeb.Staff.BookingsLive do
  @moduledoc "Booking requests (tables, groups, events, collabs, VIP). Staff call back and move each along."
  use TheGameWeb, :live_view
  import TheGameWeb.StaffComponents
  alias TheGame.{Bookings, Payments}
  alias TheGameWeb.BookingHTML

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Bookings.subscribe()
    {:ok, socket |> assign(page_title: "Bookings — THE GAME staff") |> load()}
  end

  @impl true
  def handle_info({tag, _}, socket) when tag in [:booking, :booking_updated],
    do: {:noreply, load(socket)}

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set", %{"id" => id, "to" => to}, socket) do
    status = Enum.find([:contacted, :confirmed, :declined, :closed], &(Atom.to_string(&1) == to))
    if status, do: Bookings.set_status(id, status)
    {:noreply, load(socket)}
  end

  defp load(socket) do
    assign(socket,
      bookings: Bookings.list_open(),
      reviews: length(Payments.list_reviews())
    )
  end

  defp when_text(%{on_date: nil}), do: nil

  defp when_text(%{on_date: d, at_time: t}) do
    date = Calendar.strftime(d, "%a %d %b")
    if t, do: date <> ", " <> Calendar.strftime(t, "%H:%M"), else: date
  end

  defp detail(b) do
    [
      b.party_size && "#{b.party_size} guests",
      b.event_type && BookingHTML.event_type_label(b.event_type),
      b.vip_option && BookingHTML.vip_label(b.vip_option),
      b.seating && b.seating != :any && BookingHTML.seating_label(b.seating),
      b.collab_type && BookingHTML.collab_label(b.collab_type),
      b.org,
      b.budget && "Budget " <> b.budget
    ]
    |> Enum.filter(& &1)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header active={:bookings} paused={@paused} reviews={@reviews} bookings={@new_bookings} />
    <main id="main" class="wrap swide">
      <h1 class="h1">Booking requests</h1>
      <p :if={@bookings == []} class="none">
        Nothing waiting. New requests appear here by themselves.
      </p>

      <article
        :for={b <- @bookings}
        class={["scard", b.status == :new && "warn", b.status == :confirmed && "go"]}
        id={"b-" <> b.id}
      >
        <div class="scard-h">
          <span class="bname">{b.name}</span>
          <span class="sage">{b.ref} · {age(b.inserted_at)}</span>
        </div>
        <div class="bmeta">
          <span class={["btag", b.status]}>{b.status}</span>
          <span class="btag">{BookingHTML.kind_text(b.kind)}</span>
          <span :if={when_text(b)} class="btag">{when_text(b)}</span>
          <span :for={d <- detail(b)} class="btag">{d}</span>
        </div>
        <p :if={b.message} class="bmsg">{b.message}</p>
        <dl class="kv">
          <div>
            <dt>Phone</dt>
            <dd class="mono">{b.phone}</dd>
          </div>
          <div :if={b.email}>
            <dt>Email</dt>
            <dd>{b.email}</dd>
          </div>
        </dl>
        <div class="sact">
          <a class="sbtn" href={"tel:+" <> b.phone}>Call</a>
          <a
            class="sbtn"
            href={"https://wa.me/" <> b.phone <> "?text=" <> URI.encode("Hi " <> b.name <> ", this is THE GAME about your request " <> b.ref)}
            rel="noopener"
          >
            WhatsApp
          </a>
        </div>
        <div class="sact" style="margin-top:8px">
          <button
            :if={b.status == :new}
            class="sbtn"
            phx-click="set"
            phx-value-id={b.id}
            phx-value-to="contacted"
          >
            Contacted
          </button>
          <button
            :if={b.status != :confirmed}
            class="sbtn go"
            phx-click="set"
            phx-value-id={b.id}
            phx-value-to="confirmed"
          >
            Confirm
          </button>
          <button
            :if={b.status != :confirmed}
            class="sbtn"
            phx-click="set"
            phx-value-id={b.id}
            phx-value-to="declined"
            data-confirm="Decline this request?"
          >
            Decline
          </button>
          <button
            :if={b.status == :confirmed}
            class="sbtn"
            phx-click="set"
            phx-value-id={b.id}
            phx-value-to="closed"
          >
            Done
          </button>
        </div>
      </article>
    </main>
    """
  end
end
