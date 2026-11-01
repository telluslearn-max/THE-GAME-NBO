defmodule TheGameWeb.Staff.BoardLive do
  @moduledoc "The bar's queue. New paid orders ring a bell; one tap moves an order along."
  use TheGameWeb, :live_view
  import TheGameWeb.StaffComponents
  alias TheGame.{Orders, Payments}

  @next %{"preparing" => :preparing, "ready" => :ready, "completed" => :completed}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Orders.subscribe_staff()
      Process.send_after(self(), :tick, 30_000)
    end

    {:ok, socket |> assign(page_title: "Board — THE GAME staff", code: "", found: []) |> load()}
  end

  @impl true
  def handle_info({:order_updated, _}, socket), do: {:noreply, load(socket)}

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 30_000)
    {:noreply, load(socket)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("advance", %{"id" => id, "to" => to}, socket) do
    with to when not is_nil(to) <- @next[to],
         {:ok, _} <- Orders.transition(id, to) do
      {:noreply, load(socket)}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "That order can’t move there. The board has been refreshed.")
         |> load()}
    end
  end

  def handle_event("find", %{"code" => code}, socket) do
    code = String.trim(code)
    found = if String.length(code) >= 3, do: Orders.find_by_code(code), else: []
    {:noreply, assign(socket, code: code, found: found)}
  end

  defp load(socket) do
    queue = Orders.queue()

    assign(socket,
      paid: Enum.filter(queue, &(&1.status == :paid)),
      preparing: Enum.filter(queue, &(&1.status == :preparing)),
      ready: Enum.filter(queue, &(&1.status == :ready)),
      flagged: Enum.filter(queue, &(&1.status == :flagged)),
      reviews: length(Payments.list_reviews())
    )
  end

  attr :o, :map, required: true
  attr :actions, :list, default: []

  defp card(assigns) do
    ~H"""
    <article
      class={["scard", @o.status == :ready && "go", @o.status == :flagged && "warn"]}
      id={"o-" <> @o.id}
    >
      <div class="scard-h">
        <span class="scode">{@o.pickup_code}</span>
        <span class="sage">{age(@o.paid_at || @o.inserted_at)}</span>
      </div>
      <ul class="slines">
        <li :for={i <- @o.items}><b>{i.qty}×</b> {i.name}</li>
      </ul>
      <div class="sact">
        <button
          :for={{label, to, kind} <- @actions}
          class={["sbtn", kind]}
          phx-click="advance"
          phx-value-id={@o.id}
          phx-value-to={to}
          phx-disable-with="…"
        >
          {label}
        </button>
        <a :if={@o.status == :flagged} class="sbtn" href={~p"/staff/reviews"}>Open payments</a>
      </div>
    </article>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header active={:board} paused={@paused} reviews={@reviews} />
    <main id="main" class="wrap swide" id-hook="board">
      <p :if={Phoenix.Flash.get(@flash, :error)} class="notice" role="alert">
        {Phoenix.Flash.get(@flash, :error)}
      </p>

      <form phx-change="find" phx-submit="find" class="sfind">
        <label class="sr" for="code">Find an order by code</label>
        <input
          id="code"
          class="text"
          name="code"
          value={@code}
          placeholder="Find by code"
          autocomplete="off"
          autocapitalize="characters"
          maxlength="6"
          phx-debounce="150"
        />
      </form>

      <div :if={@found != []} class="sfound">
        <p class="sh">Found</p>
        <article :for={o <- @found} class="scard">
          <div class="scard-h">
            <span class="scode">{o.pickup_code}</span><span class="sage">{o.status} · {eat(o.inserted_at)}</span>
          </div>
          <ul class="slines">
            <li :for={i <- o.items}><b>{i.qty}×</b> {i.name}</li>
          </ul>
          <div class="sage">
            {TheGame.Catalog.money(o.total_cents)} · {o.payer_phone} {o.mpesa_receipt &&
              "· " <> o.mpesa_receipt}
          </div>
        </article>
      </div>
      <p :if={@code != "" and String.length(@code) >= 3 and @found == []} class="help">
        No order with that code.
      </p>

      <div id="board" class="board" phx-hook="QueueBell" data-new={length(@paid)}>
        <section>
          <h2 class="sh">New <span class="n">{length(@paid)}</span></h2>
          <p :if={@paid == []} class="none">Nothing new.</p>
          <.card
            :for={o <- @paid}
            o={o}
            actions={[{"Start", "preparing", ""}, {"Ready", "ready", "go"}]}
          />
        </section>
        <section>
          <h2 class="sh">Preparing <span class="n">{length(@preparing)}</span></h2>
          <p :if={@preparing == []} class="none">Nothing in progress.</p>
          <.card :for={o <- @preparing} o={o} actions={[{"Ready", "ready", "go"}]} />
        </section>
        <section>
          <h2 class="sh">Ready <span class="n">{length(@ready)}</span></h2>
          <p :if={@ready == []} class="none">Nothing waiting for pickup.</p>
          <.card :for={o <- @ready} o={o} actions={[{"Collected", "completed", ""}]} />
        </section>
        <section :if={@flagged != []}>
          <h2 class="sh warn">Needs you <span class="n">{length(@flagged)}</span></h2>
          <.card :for={o <- @flagged} o={o} />
        </section>
      </div>
    </main>
    """
  end
end
