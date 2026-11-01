defmodule TheGame.MenuCache do
  @moduledoc """
  Read-through cache of the public menu. The menu is read on every visit and changes only
  when staff edit it or stock moves, so on a busy night one query serves hundreds of phones.
  Any `:menu_changed` broadcast bumps a version; a result computed against an older version is
  never stored, so a slow reader can't resurrect stale stock.
  """
  use GenServer
  @table __MODULE__

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :ets.insert(@table, {:version, 0})
    Phoenix.PubSub.subscribe(TheGame.PubSub, "menu")
    {:ok, nil}
  end

  @impl true
  def handle_info(:menu_changed, state) do
    :ets.update_counter(@table, :version, 1)
    :ets.delete(@table, :menu)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @doc "Drop the cached menu (used by tests and after bulk imports)."
  def clear do
    :ets.update_counter(@table, :version, 1)
    :ets.delete(@table, :menu)
    :ok
  end

  @doc "The menu, computed by `fun` on a miss."
  def fetch(fun) do
    if Application.get_env(:the_game, :menu_cache, true), do: cached(fun), else: fun.()
  end

  defp cached(fun) do
    case :ets.lookup(@table, :menu) do
      [{:menu, menu}] ->
        menu

      [] ->
        [{:version, v}] = :ets.lookup(@table, :version)
        menu = fun.()

        case :ets.lookup(@table, :version) do
          [{:version, ^v}] -> :ets.insert(@table, {:menu, menu})
          _ -> :ok
        end

        menu
    end
  end
end
