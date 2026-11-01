defmodule TheGame.InsightsTest do
  use TheGame.DataCase, async: false
  import TheGame.Fixtures
  alias TheGame.{Insights, Orders, Repo}
  alias TheGame.Orders.Order

  # A fixed "now": Sunday 2026-11-01 15:00 UTC = 18:00 EAT.
  @now ~U[2026-11-01 15:00:00Z]

  # Place an order and make it paid at a chosen UTC time, optionally with extras.
  defp sale(items, paid_at, opts \\ []) do
    {:ok, o} =
      Orders.create_order(
        order_attrs(items, %{payer_phone: Keyword.get(opts, :phone, unique_phone())})
      )

    {:ok, _} = Orders.mark_paid(o.id, "R#{System.unique_integer([:positive])}")

    changes =
      [paid_at: paid_at, inserted_at: paid_at]
      |> Keyword.merge(Keyword.take(opts, [:payment_method, :claimed_by_name, :completed_at]))
      |> then(fn c ->
        if opts[:completed_at], do: Keyword.put(c, :status, :completed), else: c
      end)

    Repo.update_all(from(x in Order, where: x.id == ^o.id), set: changes)
    o.id
  end

  setup do
    gin = product(%{name: "Gin", price_cents: 100_000})
    coke = product(%{name: "Coke", price_cents: 10_000})
    cold = product(%{name: "Never Sold", price_cents: 50_000})
    low = product(%{name: "Nearly Out", price_cents: 20_000, stock: 2})
    {:ok, gin: gin, coke: coke, cold: cold, low: low}
  end

  test "range starts at EAT midnight" do
    assert Insights.range_start(:today, @now) == ~U[2026-10-31 21:00:00Z]
    assert Insights.range_start(:week, @now) == ~U[2026-10-25 21:00:00Z]
    assert Insights.range_start(:month, @now) == ~U[2026-10-02 21:00:00Z]
    assert Insights.range_start(:all, @now) < ~U[2001-01-01 00:00:00Z]
  end

  test "headline numbers add up", %{gin: gin, coke: coke} do
    # today 12:00 EAT, two phones; one of them buys again later today
    sale([{gin, 2}, {coke, 1}], ~U[2026-11-01 09:00:00Z], phone: "0711111111")
    sale([{coke, 3}], ~U[2026-11-01 10:00:00Z], phone: "0722222222")
    sale([{gin, 1}], ~U[2026-11-01 12:00:00Z], phone: "0711111111")

    %{kpi: k} = Insights.summary(:today, @now)
    assert k.orders == 3
    assert k.revenue_cents == 210_000 + 30_000 + 100_000
    assert k.units == 2 + 1 + 3 + 1
    assert k.avg_order_cents == div(340_000, 3)
    assert k.customers == 2
    assert k.repeat_customers == 1
  end

  test "only paid sales count: unpaid, cancelled and expired orders are not revenue", %{gin: gin} do
    sale([{gin, 1}], ~U[2026-11-01 09:00:00Z])
    {:ok, _unpaid} = Orders.create_order(order_attrs([{gin, 1}], %{payer_phone: unique_phone()}))
    {:ok, c} = Orders.create_order(order_attrs([{gin, 1}], %{payer_phone: unique_phone()}))
    Orders.cancel(c.id)

    s = Insights.summary(:all, DateTime.utc_now())
    assert s.kpi.orders == 1
    assert s.kpi.revenue_cents == 100_000
    assert s.funnel.created == 3
    assert s.funnel.paid == 1
    assert s.funnel.cancelled == 1
    assert s.funnel.waiting == 1
    assert s.funnel.conversion_pct == 33
  end

  test "ranges include or exclude sales by EAT day", %{gin: gin} do
    sale([{gin, 1}], ~U[2026-11-01 09:00:00Z])
    # 23:30 UTC on 31 Oct = 02:30 EAT on 1 Nov: still "today" in Nairobi
    sale([{gin, 1}], ~U[2026-10-31 23:30:00Z])
    # 20:00 UTC on 31 Oct = 23:00 EAT on 31 Oct: yesterday in Nairobi
    sale([{gin, 1}], ~U[2026-10-31 20:00:00Z])
    sale([{gin, 1}], ~U[2026-10-20 09:00:00Z])

    assert Insights.summary(:today, @now).kpi.orders == 2
    assert Insights.summary(:week, @now).kpi.orders == 3
    assert Insights.summary(:month, @now).kpi.orders == 4
    assert Insights.summary(:all, @now).kpi.orders == 4
  end

  test "by_day has a row for every day, quiet days at zero", %{gin: gin} do
    sale([{gin, 1}], ~U[2026-11-01 09:00:00Z])
    sale([{gin, 2}], ~U[2026-10-29 09:00:00Z])
    days = Insights.summary(:week, @now).by_day
    assert length(days) == 7
    assert List.last(days) == %{day: ~D[2026-11-01], orders: 1, cents: 100_000}
    assert Enum.find(days, &(&1.day == ~D[2026-10-29])).cents == 200_000

    assert Enum.find(days, &(&1.day == ~D[2026-10-30])) == %{
             day: ~D[2026-10-30],
             orders: 0,
             cents: 0
           }
  end

  test "by_hour is in Nairobi time", %{gin: gin} do
    sale([{gin, 1}], ~U[2026-11-01 19:30:00Z], phone: "0711000001")
    sale([{gin, 1}], ~U[2026-11-01 19:45:00Z], phone: "0711000002")
    hours = Insights.summary(:all, ~U[2026-11-02 00:00:00Z]).by_hour
    assert length(hours) == 24
    # 19:30 UTC = 22:30 EAT
    assert Enum.find(hours, &(&1.hour == 22)).orders == 2
    assert Enum.find(hours, &(&1.hour == 19)).orders == 0
  end

  test "top products, unsold items and low stock", %{gin: gin, coke: coke, cold: cold, low: low} do
    sale([{gin, 2}, {coke, 5}], ~U[2026-11-01 09:00:00Z])
    sale([{coke, 1}], ~U[2026-11-01 10:00:00Z])

    s = Insights.summary(:today, @now)

    assert [%{name: "Coke", qty: 6, cents: 60_000}, %{name: "Gin", qty: 2, cents: 200_000}] =
             s.products

    assert cold.name in s.unsold
    assert low.name in s.unsold
    refute gin.name in s.unsold
    assert %{name: "Nearly Out", stock: 2} in s.low_stock
    refute Enum.any?(s.low_stock, &(&1.name == "Gin"))
  end

  test "payment mix: till vs prompt", %{gin: gin} do
    sale([{gin, 1}], ~U[2026-11-01 09:00:00Z], payment_method: "till")
    sale([{gin, 2}], ~U[2026-11-01 09:10:00Z], payment_method: "till")
    sale([{gin, 1}], ~U[2026-11-01 09:20:00Z])

    assert [
             %{method: "till", orders: 2, cents: 300_000},
             %{method: "prompt", orders: 1, cents: 100_000}
           ] = Insights.summary(:today, @now).methods
  end

  test "service speed and orders per waiter", %{gin: gin} do
    sale([{gin, 1}], ~U[2026-11-01 09:00:00Z],
      claimed_by_name: "Amina",
      completed_at: ~U[2026-11-01 09:10:00Z]
    )

    sale([{gin, 1}], ~U[2026-11-01 10:00:00Z],
      claimed_by_name: "amina",
      completed_at: ~U[2026-11-01 10:20:00Z]
    )

    sale([{gin, 1}], ~U[2026-11-01 11:00:00Z], claimed_by_name: "Brian")
    sale([{gin, 1}], ~U[2026-11-01 11:30:00Z])

    s = Insights.summary(:today, @now)
    assert s.speed.delivered == 2
    assert s.speed.avg_min == 15.0
    assert s.speed.median_min == 15.0
    # names are grouped case-insensitively; unclaimed orders are not attributed to anyone
    assert [%{orders: 2, delivered: 2}, %{name: "Brian", orders: 1, delivered: 0}] = s.waiters
  end

  test "an empty bar gives zeros, not errors" do
    s = Insights.summary(:all, @now)

    assert s.kpi == %{
             revenue_cents: 0,
             orders: 0,
             units: 0,
             avg_order_cents: 0,
             customers: 0,
             repeat_customers: 0
           }

    assert s.speed == %{delivered: 0, avg_min: nil, median_min: nil}
    assert s.products == [] and s.waiters == [] and s.methods == []
    assert s.funnel.conversion_pct == 0
    assert length(s.by_hour) == 24
  end
end
