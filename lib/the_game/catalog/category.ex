defmodule TheGame.Catalog.Category do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "categories" do
    field :name, :string
    field :slug, :string
    field :position, :integer, default: 0
    many_to_many :products, TheGame.Catalog.Product, join_through: "product_categories"
    timestamps()
  end
end
