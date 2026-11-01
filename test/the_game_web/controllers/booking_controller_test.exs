defmodule TheGameWeb.BookingControllerTest do
  use TheGameWeb.ConnCase
  alias TheGame.Bookings

  defp good(extra \\ %{}) do
    d = Date.to_iso8601(Date.add(Bookings.today(), 3))

    Map.merge(
      %{
        "name" => "Amina",
        "phone" => "0712345678",
        "party_size" => "4",
        "on_date" => d,
        "at_time" => "20:30"
      },
      extra
    )
  end

  test "the hub lists every kind and the VIP section", %{conn: conn} do
    html = conn |> get(~p"/book") |> html_response(200)

    for k <- ~w(table group event collab vip), do: assert(html =~ ~s(href="/book/#{k}"))
    assert html =~ "VIP experience"
    assert html =~ "Birthdays, corporate parties, afterparties, graduations"
    assert html =~ "Brands and creators"
  end

  test "the menu links to booking", %{conn: conn} do
    assert conn |> get(~p"/") |> html_response(200) =~ ~s(href="/book")
  end

  test "every form renders with labelled fields and the hidden trap", %{conn: conn} do
    for k <- ~w(table group event collab vip) do
      html = conn |> get("/book/#{k}") |> html_response(200)
      assert html =~ ~s(name="booking[name]")
      assert html =~ ~s(name="booking[phone]")
      assert html =~ ~s(name="booking[website]")
      assert html =~ "_csrf_token"
    end

    assert conn |> get("/book/table") |> html_response(200) =~ ~s(max="9")
    assert conn |> get("/book/collab") |> html_response(200) =~ ~s(name="booking[collab_type]")
    refute conn |> get("/book/collab") |> html_response(200) =~ ~s(name="booking[on_date]")
  end

  test "an unknown kind is a 404", %{conn: conn} do
    assert conn |> get("/book/banquet") |> html_response(404)
    assert conn |> post("/book/banquet", %{}) |> html_response(404)
  end

  test "a good request is stored and the thanks page says it is not confirmed yet", %{conn: conn} do
    conn = post(conn, ~p"/book/table", %{"booking" => good()})
    path = redirected_to(conn)
    assert "/book/thanks/" <> ref = path
    assert %{status: :new, phone: "254712345678"} = Bookings.get_by_ref(ref)

    html = build_conn() |> get(path) |> html_response(200)
    assert html =~ ref
    assert html =~ "Not confirmed yet"
    refute html =~ "254712345678"
  end

  test "a bad request re-renders with errors and keeps what was typed", %{conn: conn} do
    html =
      conn
      |> post(~p"/book/table", %{"booking" => good(%{"phone" => "nope", "name" => "Amina K"})})
      |> html_response(422)

    assert html =~ "Kenyan mobile number"
    assert html =~ ~s(value="Amina K")
    assert Bookings.count_new() == 0
  end

  test "a bot that fills the hidden field is thanked and nothing is stored", %{conn: conn} do
    conn = post(conn, ~p"/book/table", %{"booking" => good(%{"website" => "http://spam"})})
    assert "/book/thanks/" <> _ = redirected_to(conn)
    assert Bookings.count_new() == 0
  end

  test "the thanks page shows a WhatsApp link only when configured", %{conn: conn} do
    refute conn |> get("/book/thanks/ABC234") |> html_response(200) =~ "wa.me"
    Application.put_env(:the_game, :venue_whatsapp, "254700111222")
    on_exit(fn -> Application.delete_env(:the_game, :venue_whatsapp) end)
    assert conn |> get("/book/thanks/ABC234") |> html_response(200) =~ "wa.me/254700111222"
  end
end
