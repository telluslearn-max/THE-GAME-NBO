defmodule TheGameWeb.Staff.BoardLive do
  @moduledoc "The bar's queue. New paid orders ring a bell; one tap moves an order along."
  use TheGameWeb, :live_view
  import TheGameWeb.StaffComponents
  alias TheGame.{Orders, Payments}

  @next %{"preparing" => :preparing, "ready" => :ready}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Orders.subscribe_staff()
      Process.send_after(self(), :tick, 30_000)
    end

    {:ok,
     socket
     |> assign(page_title: "Board — THE GAME staff", code: "", found: [], waiter: "")
     |> load()}
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
    {:noreply, socket |> assign(code: String.trim(code)) |> refind()}
  end

  # The waiter's name lives in the browser (remembered between visits); no accounts.
  def handle_event("set_waiter", %{"waiter" => name}, socket) do
    {:noreply, assign(socket, waiter: name |> String.trim() |> String.slice(0, 30))}
  end

  def handle_event("claim", %{"id" => id}, socket) do
    case Orders.claim(id, socket.assigns.waiter) do
      {:ok, _} ->
        {:noreply, socket |> clear_flash() |> load() |> refind()}

      {:error, :name_required} ->
        {:noreply, put_flash(socket, :error, "Type your name in the box at the top first.")}

      {:error, {:claimed, who}} ->
        {:noreply,
         socket |> put_flash(:error, "#{who} already has that order.") |> load() |> refind()}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "That order can’t be claimed any more.")
         |> load()
         |> refind()}
    end
  end

  def handle_event("release", %{"id" => id}, socket) do
    Orders.release(id)
    {:noreply, socket |> load() |> refind()}
  end

  def handle_event("deliver", %{"id" => id}, socket) do
    case Orders.deliver(id) do
      {:ok, _} ->
        {:noreply, socket |> clear_flash() |> load() |> refind()}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "That order can’t be marked delivered. The board has been refreshed."
         )
         |> load()
         |> refind()}
    end
  end

  defp refind(%{assigns: %{code: code}} = socket) do
    assign(socket, found: if(String.length(code) >= 4, do: Orders.lookup(code), else: []))
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
  attr :waiter, :string, default: ""

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
      <p :if={@o.mpesa_receipt} class="spay">
        {TheGame.Catalog.money(@o.total_cents)} · {eat(@o.paid_at)} · M-Pesa
        <b class="mono">{@o.mpesa_receipt}</b>
      </p>
      <p :if={@o.status == :completed} class="spay">
        Delivered{@o.claimed_by_name && " by " <> @o.claimed_by_name}
      </p>
      <div :if={@o.status in [:paid, :preparing, :ready]} class="sact">
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
      </div>
      <div :if={@o.status in [:paid, :preparing, :ready]} class="sact serve">
        <button
          :if={is_nil(@o.claimed_by_name)}
          class="sbtn mine"
          phx-click="claim"
          phx-value-id={@o.id}
        >
          I’ve got this one
        </button>
        <span :if={@o.claimed_by_name} class="chip-serve">
          {if same_name?(@o.claimed_by_name, @waiter),
            do: "You have this",
            else: @o.claimed_by_name <> " has this"}
        </span>
        <button
          :if={@o.claimed_by_name && same_name?(@o.claimed_by_name, @waiter)}
          class="linkbtn"
          phx-click="release"
          phx-value-id={@o.id}
        >
          Give back
        </button>
        <button class="sbtn" phx-click="deliver" phx-value-id={@o.id} phx-disable-with="…">
          Delivered
        </button>
      </div>
      <a :if={@o.status == :flagged} class="sbtn" href={~p"/staff/reviews"}>Open payments</a>
    </article>
    """
  end

  defp same_name?(a, b),
    do: is_binary(a) and is_binary(b) and b != "" and String.downcase(a) == String.downcase(b)

  @impl true
  def render(assigns) do
    ~H"""
    <.header active={:board} paused={@paused} reviews={@reviews} />
    <main id="main" class="wrap swide" id-hook="board">
      <p :if={Phoenix.Flash.get(@flash, :error)} class="notice" role="alert">
        {Phoenix.Flash.get(@flash, :error)}
      </p>

      <form
        id="waiter-form"
        phx-hook="WaiterName"
        phx-change="set_waiter"
        phx-submit="set_waiter"
        class="sfind who"
      >
        <label class="sr" for="waiter">Your name (for “I’ve got this one”)</label>
        <input
          id="waiter"
          class="text"
          name="waiter"
          placeholder="Your name"
          autocomplete="off"
          maxlength="30"
          phx-debounce="200"
        />
      </form>

      <form phx-change="find" phx-submit="find" class="sfind">
        <label class="sr" for="code">Find an order by code</label>
        <input
          id="code"
          class="text"
          name="code"
          value={@code}
          placeholder="Find by code or M-Pesa ending"
          autocomplete="off"
          autocapitalize="characters"
          maxlength="14"
          phx-debounce="150"
        />
      </form>

      <div :if={@found != []} class="sfound">
        <p class="sh">Found</p>
        <.card
          :for={o <- @found}
          o={o}
          waiter={@waiter}
          actions={
            if o.status == :paid,
              do: [{"Start", "preparing", ""}, {"Ready", "ready", "go"}],
              else: if(o.status == :preparing, do: [{"Ready", "ready", "go"}], else: [])
          }
        />
      </div>
      <p :if={String.length(@code) >= 4 and @found == []} class="help">
        No order with that code.
      </p>

      <div id="board" class="board" phx-hook="QueueBell" data-new={length(@paid)}>
        <section>
          <h2 class="sh">New <span class="n">{length(@paid)}</span></h2>
          <p :if={@paid == []} class="none">Nothing new.</p>
          <.card
            :for={o <- @paid}
            o={o}
            waiter={@waiter}
            actions={[{"Start", "preparing", ""}, {"Ready", "ready", "go"}]}
          />
        </section>
        <section>
          <h2 class="sh">Preparing <span class="n">{length(@preparing)}</span></h2>
          <p :if={@preparing == []} class="none">Nothing in progress.</p>
          <.card :for={o <- @preparing} o={o} waiter={@waiter} actions={[{"Ready", "ready", "go"}]} />
        </section>
        <section>
          <h2 class="sh">Ready <span class="n">{length(@ready)}</span></h2>
          <p :if={@ready == []} class="none">Nothing waiting to be delivered.</p>
          <.card :for={o <- @ready} o={o} waiter={@waiter} />
        </section>
        <section :if={@flagged != []}>
          <h2 class="sh warn">Needs you <span class="n">{length(@flagged)}</span></h2>
          <.card :for={o <- @flagged} o={o} waiter={@waiter} />
        </section>
      </div>
    </main>
    """
  end
end
