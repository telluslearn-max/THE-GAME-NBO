defmodule TheGame.Push.Memory do
  @moduledoc "Test/dev sender: records deliveries instead of calling a push service."
  @behaviour TheGame.Push
  use Agent

  def start_link(_), do: Agent.start_link(fn -> [] end, name: __MODULE__)
  def sent, do: Agent.get(__MODULE__, &Enum.reverse/1)
  def reset, do: Agent.update(__MODULE__, fn _ -> [] end)
  def expire_next, do: Agent.update(__MODULE__, &[:expire | &1])

  @impl true
  def deliver(sub, payload) do
    Agent.get_and_update(__MODULE__, fn
      [:expire | rest] -> {{:error, :expired}, rest}
      state -> {:ok, [{sub, payload} | state]}
    end)
  end
end
