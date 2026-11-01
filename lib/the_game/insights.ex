defmodule TheGame.Insights do
  @moduledoc """
  Read-only business figures for the admin Insights page. Everything is computed from orders,
  items and products that already exist, in East Africa Time (UTC+3), and nothing here writes.

  "Paid" means an order that reached paid, preparing, ready or completed. Orders held for a
  payment review, refunded/closed, expired or cancelled orders are not revenue.
  """
  import Ecto.Query
  alias TheGame.Catalog.Product
  alias TheGame.Orders.{Item, Order}
  alias TheGame.Repo

  @paid [:paid, :preparing, :ready, :completed]
  @eat 3 * 3600

  @ranges %{today: 1, week: 7, month: 30, all: nil}
  def ranges, do: Map.keys(@ranges)

  @doc "Start of the range as a UTC datetime (EAT midnight of the first day)."
  def range_start(range, now \\ DateTime.utc_now()) do
    case Map.fetch!(@ranges, range) do
      nil ->
        ~U[2000-01-01 00:00:00Z]

      days ->
        eat = DateTime.add(now, @eat)
        midnight = %{eat | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
        midnight |> DateTime.add(-(days - 1) * 86_400) |> DateTime.add(-@eat)
    end
  end

  @spec summary(atom, DateTime.t()) :: map
  def summary(range, now \\ DateTime.utc_now()) do
    from = range_start(range, now)

    %{
      range: range,
      from: from,
      kpi: kpi(from),
      methods: methods(from),
      by_day: by_day(from, range, now),
      by_hour: by_hour(from),
      products: products(from),
      unsold: unsold(from),
      low_stock: low_stock(),
      funnel: funnel(from),
      speed: speed(from),
      waiters: waiters(from)
    }
  end

  defp paid_orders(from), do: from(o in Order, where: o.status in ^@paid and o.paid_at >= ^from)

  defp kpi(from) do
    %{orders: n, cents: cents, customers: customers} =
      from(o in paid_orders(from),
        select: %{
          orders: count(o.id),
          cents: coalesce(sum(o.total_cents), 0),
          customers: count(o.payer_phone, :distinct)
        }
      )
      |> Repo.one()

    units =
      from(i in Item,
        join: o in subquery(paid_orders(from)),
        on: o.id == i.order_id,
        select: coalesce(sum(i.qty), 0)
      )
      |> Repo.one()

    repeat =
      from(o in paid_orders(from),
        group_by: o.payer_phone,
        having: count(o.id) >= 2,
        select: o.payer_phone
      )
      |> Repo.all()
      |> length()

    %{
      revenue_cents: to_int(cents),
      orders: n,
      units: to_int(units),
      avg_order_cents: if(n > 0, do: div(to_int(cents), n), else: 0),
      customers: customers,
      repeat_customers: repeat
    }
  end

  defp methods(from) do
    from(o in paid_orders(from),
      group_by: o.payment_method,
      select: %{
        method: o.payment_method,
        orders: count(o.id),
        cents: coalesce(sum(o.total_cents), 0)
      }
    )
    |> Repo.all()
    |> Enum.map(fn m -> %{m | method: m.method || "prompt", cents: to_int(m.cents)} end)
    |> Enum.sort_by(&(-&1.cents))
  end

  # One row per EAT day in range, including quiet days, so a chart has no gaps.
  defp by_day(from, range, now) do
    rows =
      from(o in paid_orders(from),
        group_by: fragment("date(? + interval '3 hours')", o.paid_at),
        select:
          {fragment("date(? + interval '3 hours')", o.paid_at), count(o.id),
           coalesce(sum(o.total_cents), 0)}
      )
      |> Repo.all()
      |> Map.new(fn {d, n, c} -> {d, {n, to_int(c)}} end)

    last = now |> DateTime.add(@eat) |> DateTime.to_date()

    first =
      case range do
        :all -> rows |> Map.keys() |> Enum.min(Date, fn -> last end)
        _ -> from |> DateTime.add(@eat) |> DateTime.to_date()
      end

    for day <- Date.range(first, last) do
      {n, c} = Map.get(rows, day, {0, 0})
      %{day: day, orders: n, cents: c}
    end
  end

  defp by_hour(from) do
    rows =
      from(o in paid_orders(from),
        group_by: fragment("extract(hour from ? + interval '3 hours')", o.paid_at),
        select:
          {fragment("extract(hour from ? + interval '3 hours')", o.paid_at), count(o.id),
           coalesce(sum(o.total_cents), 0)}
      )
      |> Repo.all()
      |> Map.new(fn {h, n, c} -> {to_int(h), {n, to_int(c)}} end)

    for h <- 0..23 do
      {n, c} = Map.get(rows, h, {0, 0})
      %{hour: h, orders: n, cents: c}
    end
  end

  defp products(from) do
    from(i in Item,
      join: o in subquery(paid_orders(from)),
      on: o.id == i.order_id,
      group_by: i.name,
      order_by: [desc: sum(i.qty), asc: i.name],
      limit: 10,
      select: %{name: i.name, qty: sum(i.qty), cents: sum(i.qty * i.unit_price_cents)}
    )
    |> Repo.all()
    |> Enum.map(&%{&1 | qty: to_int(&1.qty), cents: to_int(&1.cents)})
  end

  # Active menu items that sold nothing in the range: candidates to drop or promote.
  defp unsold(from) do
    sold =
      from(i in Item,
        join: o in subquery(paid_orders(from)),
        on: o.id == i.order_id,
        select: i.product_id
      )

    from(p in Product,
      where: p.active == true and p.id not in subquery(sold),
      order_by: p.name,
      select: p.name
    )
    |> Repo.all()
  end

  defp low_stock do
    from(p in Product,
      where: p.active == true and not is_nil(p.stock) and p.stock <= 3,
      order_by: [asc: p.stock, asc: p.name],
      select: %{name: p.name, stock: p.stock}
    )
    |> Repo.all()
  end

  # Of the orders placed in the range, how many ended up paid?
  defp funnel(from) do
    counts =
      from(o in Order,
        where: o.inserted_at >= ^from,
        group_by: o.status,
        select: {o.status, count(o.id)}
      )
      |> Repo.all()
      |> Map.new()

    created = counts |> Map.values() |> Enum.sum()
    paid = @paid |> Enum.map(&Map.get(counts, &1, 0)) |> Enum.sum()

    %{
      created: created,
      paid: paid,
      expired: Map.get(counts, :expired, 0),
      cancelled: Map.get(counts, :cancelled, 0),
      waiting: Map.get(counts, :pending_payment, 0),
      flagged: Map.get(counts, :flagged, 0),
      conversion_pct: if(created > 0, do: round(paid * 100 / created), else: 0)
    }
  end

  # Minutes from paid to delivered (completed orders only), median and average.
  defp speed(from) do
    row =
      from(o in Order,
        where: o.status == :completed and o.paid_at >= ^from and not is_nil(o.completed_at),
        select: %{
          n: count(o.id),
          avg: fragment("avg(extract(epoch from (? - ?)) / 60.0)", o.completed_at, o.paid_at),
          median:
            fragment(
              "percentile_cont(0.5) within group (order by extract(epoch from (? - ?)) / 60.0)",
              o.completed_at,
              o.paid_at
            )
        }
      )
      |> Repo.one()

    %{delivered: row.n, avg_min: round_num(row.avg), median_min: round_num(row.median)}
  end

  # Orders served per waiter (by the name typed on "I've got this one").
  defp waiters(from) do
    from(o in paid_orders(from),
      where: not is_nil(o.claimed_by_name),
      group_by: fragment("lower(?)", o.claimed_by_name),
      order_by: [desc: count(o.id)],
      select: %{
        name: max(o.claimed_by_name),
        orders: count(o.id),
        cents: coalesce(sum(o.total_cents), 0),
        delivered: count(o.completed_at)
      }
    )
    |> Repo.all()
    |> Enum.map(&%{&1 | cents: to_int(&1.cents)})
  end

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = d), do: d |> Decimal.round() |> Decimal.to_integer()
  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_float(n), do: round(n)

  defp round_num(nil), do: nil
  defp round_num(%Decimal{} = d), do: d |> Decimal.to_float() |> Float.round(1)
  defp round_num(n) when is_float(n), do: Float.round(n, 1)
  defp round_num(n) when is_integer(n), do: n * 1.0
end
