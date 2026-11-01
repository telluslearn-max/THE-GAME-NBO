defmodule TheGame.Catalog do
  @moduledoc "Menu read model and staff-side product management."
  import Ecto.Query
  alias TheGame.Repo
  alias TheGame.Catalog.{Category, Product}

  @doc """
  The public menu: categories in order, each with products (name, price, in_stock).
  Inactive products are hidden; a product may appear in several categories.
  """
  def menu, do: TheGame.MenuCache.fetch(&load_menu/0)

  @doc false
  def load_menu do
    rows =
      from(c in Category,
        join: pc in "product_categories",
        on: pc.category_id == c.id,
        join: p in Product,
        on: p.id == pc.product_id,
        where: p.active == true,
        order_by: [asc: c.position, asc: pc.position, asc: p.name],
        select: {c, p}
      )
      |> Repo.all()

    rows
    |> Enum.chunk_by(fn {c, _} -> c.id end)
    |> Enum.map(fn [{c, _} | _] = group ->
      %{
        id: c.id,
        name: c.name,
        slug: c.slug,
        products:
          Enum.map(group, fn {_, p} ->
            %{id: p.id, name: p.name, price_cents: p.price_cents, in_stock: Product.in_stock?(p)}
          end)
      }
    end)
  end

  def get_product!(id), do: Repo.get!(Product, id)

  def list_products, do: Repo.all(from p in Product, order_by: p.name)

  def update_product(%Product{} = p, attrs) do
    with {:ok, p} <- p |> Product.changeset(attrs) |> Repo.update() do
      Phoenix.PubSub.broadcast(TheGame.PubSub, "menu", :menu_changed)
      {:ok, p}
    end
  end

  def list_categories, do: Repo.all(from c in Category, order_by: [asc: c.position, asc: c.name])

  @doc "Create a product and list it under a category. Price is in whole KES."
  def create_product(attrs, category_id) do
    Repo.transaction(fn ->
      with {:ok, p} <- %Product{} |> Product.changeset(attrs) |> Repo.insert() do
        Repo.insert_all("product_categories", [
          %{
            category_id: Ecto.UUID.dump!(category_id),
            product_id: Ecto.UUID.dump!(p.id),
            position: 999
          }
        ])

        p
      else
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
    |> tap(fn r ->
      if match?({:ok, _}, r), do: Phoenix.PubSub.broadcast(TheGame.PubSub, "menu", :menu_changed)
    end)
  end

  def subscribe, do: Phoenix.PubSub.subscribe(TheGame.PubSub, "menu")

  def money(cents) when is_integer(cents) do
    whole = div(cents, 100)

    digits =
      whole
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

    "KES " <> digits
  end
end
