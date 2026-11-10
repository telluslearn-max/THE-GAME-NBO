defmodule TheGameWeb.MenuControllerTest do
  use TheGameWeb.ConnCase
  import TheGame.Fixtures

  test "renders the menu with prices, stock states and category rail", %{conn: conn} do
    a = product(%{name: "Gin Alpha", price_cents: 125_000})
    b = product(%{name: "Rum Bravo", stock: 0})
    category("Spirits", [a, b])

    html = conn |> get(~p"/menu") |> html_response(200)
    assert html =~ "Gin Alpha"
    assert html =~ "KES 1,250"
    assert html =~ ~s(href="#c-spirits")
    assert html =~ "Sold out"
    assert html =~ ~s(data-price="125000")
    refute html =~ "Phoenix"
  end

  test "paused ordering shows the notice and hides Add buttons", %{conn: conn} do
    category("Spirits", [product(%{name: "Gin Alpha"})])
    TheGame.Settings.pause_ordering(true)
    html = conn |> get(~p"/menu") |> html_response(200)
    assert html =~ "Ordering is paused"
    refute html =~ ~s(data-a="add")
  end
end
