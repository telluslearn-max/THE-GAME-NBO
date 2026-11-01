defmodule TheGame.Payments.Review do
  @moduledoc """
  A payment that needs a human. Created whenever money arrives that does not cleanly
  settle an order: late (after expiry/cancel), short (less than the total), extra
  (a double payment or an overpayment) or unmatched.
  """
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @kinds ~w(late unmatched extra short)a
  @statuses ~w(pending refunded closed honored)a
  def kinds, do: @kinds
  def statuses, do: @statuses

  schema "payment_reviews" do
    belongs_to :order, TheGame.Orders.Order, type: :binary_id
    field :kind, Ecto.Enum, values: @kinds
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :mpesa_receipt, :string
    field :phone, :string
    field :amount_cents, :integer
    field :note, :string
    timestamps()
  end
end
