defmodule TheGameWeb.HomeControllerTest do
  use TheGameWeb.ConnCase

  test "the front page explains ordering and links to the menu", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "Order from your table"
    assert html =~ ~s(href="/menu")
    assert html =~ ~s(href="/orders")
    assert html =~ "How it works"
  end

  test "shows the paused notice while ordering is paused", %{conn: conn} do
    TheGame.Settings.pause_ordering(true)
    assert conn |> get(~p"/") |> html_response(200) =~ "Ordering is paused"
  end
end
