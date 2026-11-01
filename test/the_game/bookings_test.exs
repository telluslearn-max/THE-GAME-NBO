defmodule TheGame.BookingsTest do
  use TheGame.DataCase
  alias TheGame.Bookings

  defp tomorrow, do: Date.add(Bookings.today(), 1)

  defp attrs(extra) do
    Map.merge(
      %{"name" => "Amina", "phone" => "0712 345 678", "on_date" => Date.to_iso8601(tomorrow())},
      Map.new(extra, fn {k, v} -> {to_string(k), v} end)
    )
  end

  test "a table request is normalised and gets a reference" do
    {:ok, b} = Bookings.create(:table, attrs(party_size: "4", at_time: "20:30"))
    assert b.phone == "254712345678"
    assert b.status == :new
    assert b.ref =~ ~r/^[2-9A-HJKMNP-Z]{6}$/
    assert b.at_time == ~T[20:30:00]
    assert Bookings.get_by_ref(String.downcase(b.ref)).id == b.id
  end

  test "table size is 1 to 9, groups are 10 and up" do
    base = %{at_time: "20:00"}

    assert {:error, cs} = Bookings.create(:table, attrs(Map.put(base, :party_size, "10")))
    assert %{party_size: [_]} = errors_on(cs)
    assert {:error, cs} = Bookings.create(:group, attrs(Map.put(base, :party_size, "9")))
    assert %{party_size: [_]} = errors_on(cs)
    assert {:ok, _} = Bookings.create(:group, attrs(Map.put(base, :party_size, "25")))
  end

  test "dates in the past or beyond a year are refused" do
    base = %{party_size: "2", at_time: "20:00"}
    past = Date.to_iso8601(Date.add(Bookings.today(), -1))
    far = Date.to_iso8601(Date.add(Bookings.today(), 400))

    assert {:error, cs} = Bookings.create(:table, attrs(Map.put(base, :on_date, past)))
    assert %{on_date: [_]} = errors_on(cs)
    assert {:error, cs} = Bookings.create(:table, attrs(Map.put(base, :on_date, far)))
    assert %{on_date: [_]} = errors_on(cs)

    assert {:ok, _} =
             Bookings.create(
               :table,
               attrs(Map.put(base, :on_date, Date.to_iso8601(Bookings.today())))
             )
  end

  test "bad phone numbers are refused" do
    assert {:error, cs} =
             Bookings.create(:table, attrs(party_size: "2", at_time: "20:00", phone: "12345"))

    assert %{phone: [_]} = errors_on(cs)
  end

  test "events need a type; collabs need a pitch and an email but no date" do
    assert {:error, cs} = Bookings.create(:event, attrs(party_size: "40"))
    assert %{event_type: [_]} = errors_on(cs)
    assert {:ok, b} = Bookings.create(:event, attrs(party_size: "40", event_type: "afterparty"))
    assert b.event_type == :afterparty

    assert {:error, cs} = Bookings.create(:collab, %{"name" => "Kito", "phone" => "0712345678"})
    errs = errors_on(cs)

    assert Map.has_key?(errs, :collab_type) and Map.has_key?(errs, :email) and
             Map.has_key?(errs, :message)

    assert {:ok, c} =
             Bookings.create(:collab, %{
               "name" => "Kito",
               "phone" => "0712345678",
               "email" => "Kito@Brand.co",
               "collab_type" => "brand",
               "org" => "Brand Co",
               "message" => "A product launch night in December for 150 guests."
             })

    assert c.on_date == nil and c.email == "kito@brand.co"
  end

  test "vip needs an option; fields foreign to the kind are dropped" do
    assert {:error, cs} = Bookings.create(:vip, attrs(party_size: "6"))
    assert %{vip_option: [_]} = errors_on(cs)

    {:ok, b} =
      Bookings.create(
        :vip,
        attrs(party_size: "6", vip_option: "bottle_service", org: "sneaky", budget: "x")
      )

    assert b.vip_option == :bottle_service
    assert b.org == nil and b.budget == nil
  end

  test "a double tap returns the same request, not a second one" do
    a = attrs(party_size: "4", at_time: "20:30")
    {:ok, one} = Bookings.create(:table, a)
    {:ok, two} = Bookings.create(:table, a)
    assert one.id == two.id
    assert Repo.aggregate(TheGame.Bookings.Booking, :count) == 1
  end

  test "a phone is capped at 5 requests an hour" do
    for i <- 1..5 do
      {:ok, _} =
        Bookings.create(
          :table,
          attrs(
            party_size: "2",
            at_time: "20:00",
            on_date: Date.to_iso8601(Date.add(Bookings.today(), i))
          )
        )
    end

    assert {:error, :too_many} =
             Bookings.create(
               :table,
               attrs(
                 party_size: "2",
                 at_time: "20:00",
                 on_date: Date.to_iso8601(Date.add(Bookings.today(), 9))
               )
             )
  end

  test "staff statuses, the open list and the new count" do
    {:ok, b} = Bookings.create(:table, attrs(party_size: "4", at_time: "20:30"))
    assert Bookings.count_new() == 1
    assert [%{id: id}] = Bookings.list_open()
    assert id == b.id

    {:ok, c} = Bookings.set_status(b.id, :confirmed)
    assert c.status == :confirmed
    assert Bookings.count_new() == 0
    assert length(Bookings.list_open()) == 1

    {:ok, _} = Bookings.set_status(b.id, :closed)
    assert Bookings.list_open() == []
    assert {:error, :not_found} = Bookings.set_status(Ecto.UUID.generate(), :closed)
    assert_raise FunctionClauseError, fn -> Bookings.set_status(b.id, :new) end
  end
end
