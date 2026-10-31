defmodule TheGame.Catalog.Product do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "products" do
    field :name, :string
    field :price_cents, :integer
    field :active, :boolean, default: true
    field :stock, :integer
    many_to_many :categories, TheGame.Catalog.Category, join_through: "product_categories"
    timestamps()
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :price_cents, :active, :stock])
    |> validate_required([:name, :price_cents])
    |> validate_number(:price_cents, greater_than: 0)
    |> validate_number(:stock, greater_than_or_equal_to: 0)
  end

  @doc "A product can be ordered when active and (untracked or stock left)."
  def in_stock?(%__MODULE__{active: true, stock: nil}), do: true
  def in_stock?(%__MODULE__{active: true, stock: s}) when s > 0, do: true
  def in_stock?(_), do: false
end
