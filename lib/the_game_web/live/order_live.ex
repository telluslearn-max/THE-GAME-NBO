defmodule TheGameWeb.OrderLive do
  @moduledoc """
  The order page: the customer's whole experience after checkout. Live over PubSub, so a
  status change at the bar reaches the phone without polling. Every payment state is explicit
  and the copy repeats the one rule that protects the customer: do not pay twice.
  """
  use TheGameWeb, :live_view
  alias TheGame.{Catalog, Orders, Payments, Phone}
  alias TheGame.Orders.Order

  @impl true
  def mount(%{"id" => id}, session, socket) do
    case Orders.get_order(id) do
      nil ->
        {:ok, assign(socket, order: nil, page_title: "Order not found — THE GAME")}

      %Order{} = order ->
        if connected?(socket), do: Orders.subscribe(order.id)

        socket =
          socket
          |> assign(confirm_cancel: false, error: nil, info: nil, busy: false)
          # Only the browser that just checked out may trigger the first prompt. Anyone else
          # holding the link (a friend, staff) can look, but never makes a phone buzz.
          |> assign(auto_pay: session["fresh_order"] == order.id)
          |> load(order)

        # First arrival after checkout: send the prompt straight away. request_stk's own
        # gates make this safe on reconnects and reloads.
        if connected?(socket) and socket.assigns.auto_pay and socket.assigns.pay == :none,
          do: send(self(), :auto_pay)

        {:ok, socket}
    end
  end

  @impl true
  def handle_info({:order_updated, %Order{} = order}, socket), do: {:noreply, load(socket, order)}
  def handle_info(:auto_pay, socket), do: {:noreply, do_pay(socket)}

  @impl true
  def handle_event("pay", _, socket), do: {:noreply, do_pay(socket)}

  def handle_event("refresh", _, socket),
    do: {:noreply, load(socket, Orders.get_order!(socket.assigns.order.id))}

  def handle_event("check", _, socket) do
    id = socket.assigns.order.id

    {info, error} =
      case Payments.check(id) do
        {:ok, :paid} ->
          {nil, nil}

        {:ok, :pending} ->
          {"Still unconfirmed by M-Pesa. If money left your account, don’t pay again. Show staff your M-Pesa message and the reference below.",
           nil}

        {:ok, :failed} ->
          {"That payment didn’t go through. You can try again.", nil}

        {:ok, :none} ->
          {nil, nil}

        {:error, _} ->
          {nil, "Couldn’t reach M-Pesa to check. Try again in a moment. Don’t pay again."}
      end

    {:noreply, socket |> assign(info: info, error: error) |> load(Orders.get_order!(id))}
  end

  def handle_event("push-subscribe", sub, socket) do
    case TheGame.Push.subscribe(socket.assigns.order.id, sub) do
      {:ok, _} -> {:reply, %{ok: true}, socket}
      {:error, _} -> {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("ask_cancel", _, socket), do: {:noreply, assign(socket, confirm_cancel: true)}
  def handle_event("keep", _, socket), do: {:noreply, assign(socket, confirm_cancel: false)}

  def handle_event("cancel", _, socket) do
    id = socket.assigns.order.id

    error =
      case Orders.cancel(id) do
        {:ok, _} -> nil
        {:error, _} -> "Couldn’t cancel this order. It may already be paid; check its status."
      end

    {:noreply,
     socket |> assign(confirm_cancel: false, error: error) |> load(Orders.get_order!(id))}
  end

  defp do_pay(socket) do
    id = socket.assigns.order.id

    {info, error} =
      case Payments.request_stk(id) do
        {:ok, _} ->
          {nil, nil}

        {:error, {:cooldown, _}} ->
          {nil, nil}

        {:error, :unresolved} ->
          {"We’re still waiting on M-Pesa for the last prompt. Tap “Check payment” before trying again.",
           nil}

        {:error, :already_paid} ->
          {nil, nil}

        {:error, :not_payable} ->
          {nil, "This order is no longer open for payment."}

        {:error, :gateway} ->
          {nil,
           "M-Pesa didn’t accept the request. Try again in a moment. You haven’t been charged."}

        {:error, _} ->
          {nil, "Something went wrong. Check the order status before trying again."}
      end

    socket |> assign(info: info, error: error) |> load(Orders.get_order!(id))
  end

  # Derive everything the template needs from the database row, so the page can never
  # disagree with the truth after a reconnect.
  defp load(socket, %Order{} = order) do
    payment = Payments.latest_payment(order.id)
    review = Payments.pending_review(order.id)

    socket
    |> assign(
      order: order,
      payment: payment,
      review: review,
      pay: pay_state(order, payment),
      page_title: "Order #{order.pickup_code} — THE GAME"
    )
  end

  defp pay_state(%Order{status: :pending_payment}, nil), do: :none

  defp pay_state(%Order{status: :pending_payment}, %{status: s} = p) when s in [:queued, :sent] do
    left = Payments.cooldown_seconds() - DateTime.diff(DateTime.utc_now(), p.inserted_at)
    if left > 0, do: {:waiting, left}, else: :unresolved
  end

  defp pay_state(%Order{status: :pending_payment}, _failed), do: :retry
  defp pay_state(_, _), do: :n_a

  ## View helpers

  def eat(%DateTime{} = dt), do: dt |> DateTime.add(3 * 3600) |> Calendar.strftime("%H:%M")
  def money(c), do: Catalog.money(c)
  def last4(phone), do: Phone.last4(phone)
  def epoch_ms(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)
  def future_ms(seconds), do: System.system_time(:millisecond) + seconds * 1000

  def headline(%{status: :pending_payment}), do: "Waiting for payment"
  def headline(%{status: :paid}), do: "Paid. The bar has your order"
  def headline(%{status: :preparing}), do: "Being prepared"

  def headline(%{status: :ready, claimed_by_name: n}) when is_binary(n),
    do: "Ready. #{n} will bring it"

  def headline(%{status: :ready}), do: "Ready. Your waiter will bring it"

  def headline(%{status: :completed, claimed_by_name: n}) when is_binary(n),
    do: "Delivered by #{n}. Enjoy"

  def headline(%{status: :completed}), do: "Delivered. Enjoy"
  def headline(%{status: :expired}), do: "Order expired"
  def headline(%{status: :cancelled}), do: "Order cancelled"
  def headline(%{status: :flagged}), do: "Staff are checking your payment"
  def headline(%{status: :closed}), do: "Order closed"

  def has_code?(%{status: s}), do: s in [:paid, :preparing, :ready, :completed]

  @impl true
  def render(%{order: nil} = assigns) do
    ~H"""
    <header class="wrap top">
      <a class="brand" href={~p"/"} aria-label="THE GAME, home"><TheGameWeb.Layouts.wordmark /></a>
    </header>
    <main id="main" class="wrap">
      <div class="empty">
        <b>Order not found</b>Check the link, or open your orders on the phone you ordered with.
      </div>
      <a class="btn" href={~p"/orders"}>Your orders</a>
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <header class="wrap top">
      <a class="brand" href={~p"/"} aria-label="THE GAME, home"><TheGameWeb.Layouts.wordmark /></a>
      <nav aria-label="Primary"><a class="navlink" href={~p"/orders"}>Orders</a></nav>
    </header>

    <main id="main" class="wrap">
      <h1 class="status" aria-live="polite">{headline(@order)}</h1>

      <div
        id="ticket"
        phx-hook="Alert"
        data-status={@order.status}
        class={[
          "ticket",
          @order.status == :ready && "go",
          @order.status in [:completed, :expired, :cancelled, :closed] && "dim"
        ]}
      >
        <span class="ticket-k">{if has_code?(@order), do: "Pickup code", else: "Reference"}</span>
        <span class="ticket-code">{@order.pickup_code}</span>
        <span class="ticket-n">
          {cond do
            @order.status == :ready -> "Give this code to your waiter"
            has_code?(@order) -> "Give this code to your waiter"
            true -> "Quote this to staff if anything goes wrong"
          end}
        </span>
      </div>

      <p
        :if={@order.claimed_by_name && @order.status in [:paid, :preparing, :ready]}
        class="served"
        aria-live="polite"
      >
        You’ll be served by <b>{@order.claimed_by_name}</b>
      </p>

      <section :if={@order.status == :pending_payment} class="panel" aria-live="polite">
        <p :if={@pay == :none and @auto_pay} class="p">
          Sending the M-Pesa prompt to the number ending <b class="mono">{last4(@order.payer_phone)}</b>…
        </p>
        <div :if={@pay == :none and !@auto_pay}>
          <p class="p">
            This order is waiting for payment of <b class="mono">{money(@order.total_cents)}</b>
            from the number ending <b class="mono">{last4(@order.payer_phone)}</b>.
          </p>
          <button class="btn" phx-click="pay" phx-disable-with="Sending…">
            Send M-Pesa prompt
          </button>
        </div>

        <div :if={match?({:waiting, _}, @pay)}>
          <p class="p">
            <b>Check your phone.</b>
            Enter your M-Pesa PIN for <b class="mono">{money(@order.total_cents)}</b>
            (number ending <b class="mono">{last4(@order.payer_phone)}</b>).
          </p>
          <% {:waiting, left} = @pay %>
          <p class="help">
            Didn’t get it? You can ask again in <b
              id="cooldown"
              class="mono"
              phx-hook="Countdown"
              data-until={future_ms(left)}
            ></b>.
          </p>
        </div>

        <div :if={@pay == :unresolved}>
          <p class="p">
            <b>We haven’t heard back from M-Pesa yet.</b>
            If money left your account, <b>don’t pay again</b>. Check the status instead.
          </p>
          <button class="btn" phx-click="check" phx-disable-with="Checking…">Check payment</button>
        </div>

        <div :if={@pay == :retry}>
          <p class="p">
            {case @payment && @payment.status do
              :cancelled -> "You cancelled the prompt."
              :timeout -> "The prompt timed out."
              _ -> "That attempt didn’t go through."
            end} Your drinks are still held.
          </p>
          <button class="btn" phx-click="pay" phx-disable-with="Sending…">
            Send M-Pesa prompt again
          </button>
        </div>

        <button
          :if={match?({:waiting, _}, @pay)}
          class="btn ghost wide"
          phx-click="check"
          phx-disable-with="Checking…"
        >
          I’ve paid. Check status
        </button>

        <p class="help">
          Held for you until <b class="mono">{eat(@order.expires_at)}</b> EAT
          (<b id="hold" class="mono" phx-hook="Countdown" data-until={epoch_ms(@order.expires_at)}></b> left).
        </p>

        <p :if={@info} class="notice" role="status">{@info}</p>
        <p :if={@error} class="notice" role="alert">{@error}</p>

        <div
          :if={@pay in [:retry, :none] or match?({:waiting, _}, @pay) or @pay == :unresolved}
          class="cancel"
        >
          <button :if={!@confirm_cancel} class="linkbtn" phx-click="ask_cancel">Cancel order</button>
          <div :if={@confirm_cancel}>
            <p class="help">
              Cancel this unpaid order? An earlier M-Pesa prompt may still arrive. If money was deducted, ask staff before cancelling or paying again.
            </p>
            <div class="row2">
              <button class="btn ghost" phx-click="cancel" phx-disable-with="Cancelling…">
                Yes, cancel
              </button>
              <button class="linkbtn" phx-click="keep">Keep order</button>
            </div>
          </div>
        </div>
      </section>

      <section :if={@order.status == :flagged or @review} class="panel" role="status">
        <p class="p">
          <b>A payment may belong to this order.</b>
          Show staff your M-Pesa message and the reference <b class="mono">{@order.pickup_code}</b>. Please don’t pay again while they check.
        </p>
      </section>

      <section :if={@order.status in [:expired, :cancelled] and !@review} class="panel">
        <p class="p">
          {if @order.status == :expired,
            do: "The hold on your drinks ran out.",
            else: "This order was cancelled."} If M-Pesa took money, show staff your M-Pesa message and the reference <b class="mono">{@order.pickup_code}</b>.
        </p>
        <a class="btn" href={~p"/"}>Start a new order</a>
      </section>

      <section :if={@order.status in [:paid, :preparing, :ready]} class="panel slim">
        <p class="help">
          M-Pesa receipt <b class="mono">{@order.mpesa_receipt}</b> · paid {eat(@order.paid_at)} EAT
        </p>
      </section>

      <div
        :if={@order.status in [:paid, :preparing] and TheGame.Push.enabled?()}
        id="push"
        class="panel slim"
        phx-hook="PushOptIn"
        phx-update="ignore"
        data-key={TheGame.Push.public_key()}
        hidden
      >
        <button type="button" class="linkbtn" data-role="enable">Notify me when it’s ready</button>
        <span class="help" data-role="on" hidden>
          You’ll get a notification when your drinks are ready.
        </span>
      </div>

      <ul class="rows">
        <li :for={i <- @order.items} class="row">
          <div>
            <span class="name">{i.qty} × {i.name}</span>
            <span class="price">{money(i.qty * i.unit_price_cents)}</span>
          </div>
        </li>
      </ul>
      <div class="total">
        <span>Total</span><output class="mono">{money(@order.total_cents)}</output>
      </div>
      <p class="help">Ordered {eat(@order.inserted_at)} EAT</p>
    </main>
    """
  end
end
