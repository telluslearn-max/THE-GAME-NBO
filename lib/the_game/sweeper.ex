defmodule TheGame.Sweeper do
  @moduledoc """
  Housekeeping tick (every 10 s): expire unpaid reservations (releasing stock) and ask
  Safaricom about prompts that never got a callback. All state lives in Postgres and every
  step takes row locks, so a restart or a second node is harmless.
  """
  use GenServer
  require Logger

  @tick 10_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    schedule(opts[:tick] || @tick)
    {:ok, %{tick: opts[:tick] || @tick}}
  end

  @impl true
  def handle_info(:tick, %{tick: tick} = state) do
    run()
    schedule(tick)
    {:noreply, state}
  end

  def run do
    expired = TheGame.Orders.expire_due()
    reconciled = TheGame.Payments.reconcile()

    if expired > 0 or reconciled > 0,
      do: Logger.info("sweeper: expired=#{expired} reconciled=#{reconciled}")

    :ok
  rescue
    e -> Logger.error("sweeper failed: " <> Exception.message(e))
  end

  defp schedule(ms), do: Process.send_after(self(), :tick, ms)
end
