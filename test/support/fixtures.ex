defmodule TheGame.Fixtures do
  alias TheGame.Repo
  alias TheGame.Catalog.{Category, Product}

  def product(attrs \\ %{}) do
    attrs = Map.new(attrs)

    %Product{
      name: "Test Spirit #{System.unique_integer([:positive])}",
      price_cents: 100_000,
      active: true
    }
    |> struct(attrs)
    |> Repo.insert!()
  end

  def category(name, products, position \\ 0) do
    cat =
      Repo.insert!(%Category{name: name, slug: String.downcase(name), position: position})

    products
    |> Enum.with_index()
    |> Enum.each(fn {p, i} ->
      Repo.insert_all("product_categories", [
        %{category_id: Ecto.UUID.dump!(cat.id), product_id: Ecto.UUID.dump!(p.id), position: i}
      ])
    end)

    cat
  end

  def order_attrs(products_qty, extra \\ %{}) do
    Map.merge(
      %{
        payer_phone: "0712 345 678",
        items: Enum.map(products_qty, fn {p, q} -> %{product_id: p.id, qty: q} end)
      },
      extra
    )
  end

  def unique_phone,
    do: "07" <> String.pad_leading("#{System.unique_integer([:positive])}", 8, "1")
end
