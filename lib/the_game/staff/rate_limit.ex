defmodule TheGame.Staff.RateLimit do
  @moduledoc """
  Login throttle: 5 failures per {email, client} in 10 minutes locks that pair out until the
  window passes. In-memory (ETS), which is right for a single-venue, single-node deployment.
  """
  use GenServer
  @table __MODULE__
  @max 5
  @window_ms 10 * 60 * 1000

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def init(_), do: {:ok, :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])}

  def blocked?(key), do: length(recent(key)) >= @max

  def hit(key), do: :ets.insert(@table, {key, [now() | recent(key)]})
  def clear(key), do: :ets.delete(@table, key)

  defp recent(key) do
    case :ets.lookup(@table, key) do
      [{_, times}] -> Enum.filter(times, &(&1 > now() - @window_ms))
      _ -> []
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
