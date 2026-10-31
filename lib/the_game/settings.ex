defmodule TheGame.Settings do
  @moduledoc "Tiny key/value store for operational switches (e.g. pause ordering)."
  import Ecto.Query
  alias TheGame.Repo

  def get(key, default \\ nil) do
    Repo.one(from s in "settings", where: s.key == ^key, select: s.value) || default
  end

  def put(key, value) when is_binary(key) and is_binary(value) do
    Repo.insert_all("settings", [%{key: key, value: value}],
      on_conflict: {:replace, [:value]},
      conflict_target: :key
    )

    Phoenix.PubSub.broadcast(TheGame.PubSub, "menu", :menu_changed)
    :ok
  end

  def ordering_paused?, do: get("ordering_paused", "false") == "true"
  def pause_ordering(paused?), do: put("ordering_paused", to_string(paused?))
end
