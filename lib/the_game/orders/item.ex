defmodule TheGame.Orders.Item do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "order_items" do
    belongs_to :order, TheGame.Orders.Order, type: :binary_id
    field :product_id, :binary_id
    field :name, :string
    field :unit_price_cents, :integer
    field :qty, :integer
  end
end
