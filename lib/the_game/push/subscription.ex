defmodule TheGame.Push.Subscription do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "push_subscriptions" do
    belongs_to :order, TheGame.Orders.Order, type: :binary_id
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string
    timestamps()
  end
end
