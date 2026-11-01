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
     |> assign(page_title: "Board — THE GAME staff", code: "", found: [], waiter: "", draft: %{})
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

  def handle_event("claim", %{"oid" => id, "last4" => last4, "time" => time}, socket) do
    # keep what she typed if something is missing, so she never retypes everything
    socket = assign(socket, draft: Map.put(socket.assigns.draft, id, %{last4: last4, time: time}))

    case Orders.claim(id, socket.assigns.waiter, last4, time) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(draft: Map.delete(socket.assigns.draft, id))
         |> clear_flash()
         |> load()
         |> refind()}

      {:error, :name_required} ->
        {:noreply, put_flash(socket, :error, "Type your name in the box at the top first.")}

      {:error, :code_required} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Type the last 4 characters of the M-Pesa code from the client’s phone."
         )}

      {:error, :time_required} ->
        {:noreply,
         put_flash(socket, :error, "Type the time paid from the client’s M-Pesa message.")}

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

  # The counter has matched the till payment on the POS: the order becomes paid and goes to the bar.
  def handle_event("confirm_till", %{"id" => id}, socket) do
    case Orders.confirm_till(id, socket.assigns.waiter) do
      {:ok, _} ->
        {:noreply, socket |> clear_flash() |> load() |> refind()}

      {:error, :name_required} ->
        {:noreply, put_flash(socket, :error, "Type your name in the box at the top first.")}

      {:error, :needs_note} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Write the client’s M-Pesa code and time first (I’ve got this one)."
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "That order can’t be confirmed any more. The board has been refreshed."
         )
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
      awaiting: Orders.awaiting_payment(),
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
  attr :draft, :map, default: %{}

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
      <p :if={@o.status in [:pending_payment, :expired]} class="spay">
        <b class={["chip-unpaid", @o.status == :expired && "gone"]}>
          {if @o.status == :expired, do: "Expired", else: "Unpaid"}
        </b>
        {TheGame.Catalog.money(@o.total_cents)} · phone …<b class="mono">{TheGame.Phone.last4(@o.payer_phone)}</b>
      </p>
      <p :if={@o.paid_at} class="spay">
        Paid <b class="mono">{eat(Orders.paid_time(@o))}</b>
        · {TheGame.Catalog.money(@o.total_cents)} · {if @o.payment_method == "till",
          do: "till",
          else: "M-Pesa"} …<b class="mono">{Orders.receipt_end(@o)}</b>
      </p>
      <p :if={@o.claimed_by_name && @o.recorded_code} class="slip">
        <span class="slip-k">{@o.claimed_by_name} wrote</span>
        <span class="slip-code">{@o.recorded_code}<i>·</i>{@o.recorded_time}</span>
        <span :if={@o.mpesa_receipt && Orders.code_matches?(@o)} class="slip-ok">✓ code matches</span>
        <span :if={@o.mpesa_receipt && !Orders.code_matches?(@o)} class="slip-no">
          code differs from the order’s
        </span>
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
      <div
        :if={@o.status in [:pending_payment, :expired, :paid, :preparing, :ready]}
        class="sact serve"
      >
        <form :if={is_nil(@o.claimed_by_name)} phx-submit="claim" class="claimform">
          <input type="hidden" name="oid" value={@o.id} />
          <input
            class="text last4"
            name="last4"
            value={get_in(@draft, [@o.id, :last4])}
            maxlength="4"
            placeholder="Last 4 of M-Pesa code"
            autocomplete="off"
            autocapitalize="characters"
            inputmode="text"
            aria-label="Last 4 characters of the M-Pesa code on the client's phone"
          />
          <input
            class="text time"
            name="time"
            value={get_in(@draft, [@o.id, :time])}
            maxlength="8"
            placeholder="Time paid"
            autocomplete="off"
            inputmode="text"
            aria-label="Time paid, as the client's M-Pesa message shows it"
          />
          <button class="sbtn mine" type="submit">I’ve got this one</button>
        </form>
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
        <button
          :if={@o.status in [:pending_payment, :expired] && @o.claimed_by_name}
          class="sbtn go"
          phx-click="confirm_till"
          phx-value-id={@o.id}
          phx-disable-with="…"
        >
          Confirmed at counter
        </button>
        <button
          :if={@o.status in [:paid, :preparing, :ready]}
          class="sbtn"
          phx-click="deliver"
          phx-value-id={@o.id}
          phx-disable-with="…"
        >
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
          draft={@draft}
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
        <section :if={@awaiting != []}>
          <h2 class="sh">Waiting for payment <span class="n">{length(@awaiting)}</span></h2>
          <.card :for={o <- @awaiting} o={o} waiter={@waiter} draft={@draft} />
        </section>
        <section>
          <h2 class="sh">New <span class="n">{length(@paid)}</span></h2>
          <p :if={@paid == []} class="none">Nothing new.</p>
          <.card
            :for={o <- @paid}
            o={o}
            waiter={@waiter}
            draft={@draft}
            actions={[{"Start", "preparing", ""}, {"Ready", "ready", "go"}]}
          />
        </section>
        <section>
          <h2 class="sh">Preparing <span class="n">{length(@preparing)}</span></h2>
          <p :if={@preparing == []} class="none">Nothing in progress.</p>
          <.card
            :for={o <- @preparing}
            o={o}
            waiter={@waiter}
            draft={@draft}
            actions={[{"Ready", "ready", "go"}]}
          />
        </section>
        <section>
          <h2 class="sh">Ready <span class="n">{length(@ready)}</span></h2>
          <p :if={@ready == []} class="none">Nothing waiting to be delivered.</p>
          <.card :for={o <- @ready} o={o} waiter={@waiter} draft={@draft} />
        </section>
        <section :if={@flagged != []}>
          <h2 class="sh warn">Needs you <span class="n">{length(@flagged)}</span></h2>
          <.card :for={o <- @flagged} o={o} waiter={@waiter} draft={@draft} />
        </section>
      </div>
    </main>
    """
  end
end
