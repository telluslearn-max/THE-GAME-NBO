defmodule TheGame.CatalogTest do
  use TheGame.DataCase, async: true
  import TheGame.Fixtures
  alias TheGame.Catalog

  test "menu groups by ordered category, hides inactive, flags stock" do
    a = product(%{name: "Alpha", stock: 0})
    b = product(%{name: "Bravo"})
    hidden = product(%{name: "Zulu", active: false})
    category("Spirits", [a, hidden], 2)
    category("Popular", [b, a], 1)

    assert [%{name: "Popular", products: [pb, pa]}, %{name: "Spirits", products: [only]}] =
             Catalog.menu()

    assert pb.name == "Bravo" and pb.in_stock
    assert pa.name == "Alpha" and not pa.in_stock
    assert only.name == "Alpha"
  end

  test "money formats KES with thousands separators" do
    assert Catalog.money(125_000) == "KES 1,250"
    assert Catalog.money(10_000) == "KES 100"
    assert Catalog.money(1_234_500_00) == "KES 1,234,500"
  end
end
