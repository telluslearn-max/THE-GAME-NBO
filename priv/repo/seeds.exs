# Dev seed. Items and prices are the ones observed on the incumbent menu (docs/STUDY.md).
# Owner must replace with the real, complete menu through the staff app.
alias TheGame.Repo
alias TheGame.Catalog.{Category, Product}

menu = [
  {"Popular", "popular",
   [{"KC Ginger", 125_000, 12}, {"KC Smooth", 125_000, 12}, {"KC Pineapple", 125_000, 0},
    {"Captain Morgan Gold", 160_000, 8}, {"Torrerro", 140_000, 6}, {"Viceroy", 210_000, 5},
    {"County", 110_000, 10}, {"Coke", 10_000, nil}, {"Lemonade", 7_000, nil},
    {"Water", 10_000, nil}, {"Oris (5 pieces)", 10_000, nil}]},
  {"Cocktails", "cocktails", [{"Love portion", 40_000, nil}, {"Summer Berry", 40_000, 0}]},
  {"Spirits", "spirits",
   [{"Viceroy", 210_000, 5}, {"KC Ginger", 125_000, 12}, {"KC Smooth", 125_000, 12},
    {"KC Pineapple", 125_000, 0}, {"Captain Morgan Gold", 160_000, 8},
    {"Torrerro", 140_000, 6}, {"County", 110_000, 10}]},
  {"Mixers", "mixers", [{"Coke", 10_000, nil}, {"Lemonade", 7_000, nil}, {"Water", 10_000, nil}]}
]

if Repo.aggregate(Category, :count) == 0 do
  products =
    menu
    |> Enum.flat_map(fn {_, _, items} -> items end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Map.new(fn {name, price, stock} ->
      {name, Repo.insert!(%Product{name: name, price_cents: price, stock: stock})}
    end)

  menu
  |> Enum.with_index()
  |> Enum.each(fn {{cat, slug, items}, ci} ->
    c = Repo.insert!(%Category{name: cat, slug: slug, position: ci})

    items
    |> Enum.with_index()
    |> Enum.each(fn {{name, _, _}, pi} ->
      Repo.insert_all("product_categories", [
        %{category_id: Ecto.UUID.dump!(c.id), product_id: Ecto.UUID.dump!(products[name].id), position: pi}
      ])
    end)
  end)
end
