defmodule TheGame.Orders.Order do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @type t :: %__MODULE__{}

  schema "orders" do
    field :status, Ecto.Enum, values: TheGame.Orders.Status.all(), default: :pending_payment
    field :phone, :string
    field :payer_phone, :string
    field :total_cents, :integer
    field :pickup_code, :string
    field :expires_at, :utc_datetime
    field :mpesa_receipt, :string
    field :paid_at, :utc_datetime
    field :ready_at, :utc_datetime
    field :completed_at, :utc_datetime
    has_many :items, TheGame.Orders.Item
    has_many :payments, TheGame.Payments.Payment
    timestamps()
  end
end
