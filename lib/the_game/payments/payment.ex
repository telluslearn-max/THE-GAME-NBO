defmodule TheGame.Payments.Payment do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  # queued -> sent -> success | failed | timeout   (cancelled = user dismissed / order cancelled)
  @statuses ~w(queued sent success failed timeout cancelled)a
  def statuses, do: @statuses

  schema "payments" do
    belongs_to :order, TheGame.Orders.Order, type: :binary_id
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :phone, :string
    field :amount_cents, :integer
    field :checkout_request_id, :string
    field :merchant_request_id, :string
    field :result_code, :integer
    field :result_desc, :string
    field :mpesa_receipt, :string
    field :sent_at, :utc_datetime
    timestamps()
  end
end
