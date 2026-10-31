defmodule TheGame.StatusTest do
  use ExUnit.Case, async: true
  alias TheGame.Orders.Status

  test "happy path is legal" do
    path = [:pending_payment, :paid, :preparing, :ready, :completed]
    for [a, b] <- Enum.chunk_every(path, 2, 1, :discard), do: assert(Status.can?(a, b))
  end

  test "money cannot appear from nowhere" do
    refute Status.can?(:pending_payment, :preparing)
    refute Status.can?(:pending_payment, :ready)
    refute Status.can?(:expired, :paid)
    refute Status.can?(:cancelled, :paid)
  end

  test "terminal states go nowhere" do
    assert Status.next(:closed) == []
    refute Status.can?(:completed, :paid)
  end

  test "every status is declared in the table" do
    for s <- Status.all(), do: assert(is_list(Status.next(s)))
  end
end
