defmodule TheGame.Orders.Status do
  @moduledoc """
  The order state machine. Pure: no database. Every transition in the system goes
  through `can?/2`, so an illegal move is impossible rather than merely unlikely.
  """

  @statuses ~w(pending_payment paid preparing ready completed expired cancelled flagged closed)a

  # from => allowed targets
  @transitions %{
    pending_payment: [:paid, :expired, :cancelled, :flagged],
    paid: [:preparing, :ready, :flagged, :closed],
    preparing: [:ready, :flagged],
    ready: [:completed, :flagged],
    flagged: [:preparing, :ready, :completed, :closed],
    completed: [:closed],
    expired: [:flagged, :closed],
    cancelled: [:closed],
    closed: []
  }

  def all, do: @statuses
  def values, do: Enum.map(@statuses, &Atom.to_string/1)
  def can?(from, to), do: to in Map.get(@transitions, from, [])
  def next(from), do: Map.get(@transitions, from, [])

  @doc "Live = still occupies a pickup code and may need staff action."
  def live?(s), do: s in [:pending_payment, :paid, :preparing, :ready, :flagged]

  @doc "Statuses where the customer has paid and the bar owes them drinks."
  def fulfilling?(s), do: s in [:paid, :preparing, :ready]

  @doc "Statuses that hold reserved stock."
  def holds_stock?(s),
    do: s in [:pending_payment, :paid, :preparing, :ready, :flagged, :completed]
end
