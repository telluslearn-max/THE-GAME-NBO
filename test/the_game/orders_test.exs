defmodule TheGame.OrdersTest do
  use TheGame.DataCase, async: false
  import TheGame.Fixtures
  alias TheGame.{Orders, Repo, Settings}
  alias TheGame.Catalog.Product

  setup do
    {:ok, gin: product(%{price_cents: 125_000, stock: 5}), coke: product(%{price_cents: 10_000})}
  end

  defp stock(p), do: Repo.get!(Product, p.id).stock

  test "creates an order, snapshots prices, reserves stock", %{gin: gin, coke: coke} do
    attrs = order_attrs([{gin, 2}, {coke, 1}], %{expected_total_cents: 260_000})
    assert {:ok, o} = Orders.create_order(attrs)
    assert o.total_cents == 260_000
    assert o.status == :pending_payment
    assert o.payer_phone == "254712345678"
    assert String.length(o.pickup_code) == 4
    assert length(o.items) == 2
    assert stock(gin) == 3
    assert stock(coke) == nil
  end

  test "rejects when the client's total is stale", %{gin: gin} do
    assert {:error, {:total_mismatch, 125_000}} =
             Orders.create_order(order_attrs([{gin, 1}], %{expected_total_cents: 100_000}))

    assert stock(gin) == 5
  end

  test "rejects sold-out and unknown products", %{gin: gin} do
    assert {:error, {:unavailable, [_]}} = Orders.create_order(order_attrs([{gin, 6}]))
    off = product(%{active: false})
    assert {:error, {:unavailable, _}} = Orders.create_order(order_attrs([{off, 1}]))
    assert stock(gin) == 5
  end

  test "caps units at 15 and validates input", %{coke: coke} do
    assert {:error, :too_many_units} = Orders.create_order(order_attrs([{coke, 16}]))
    assert {:error, :invalid_quantity} = Orders.create_order(order_attrs([{coke, 0}]))
    assert {:error, :empty} = Orders.create_order(%{payer_phone: "0712345678", items: []})

    assert {:error, :invalid_phone} =
             Orders.create_order(order_attrs([{coke, 1}], %{payer_phone: "123"}))
  end

  test "duplicate lines for one product merge", %{coke: coke} do
    attrs = %{
      payer_phone: "0712345678",
      items: [%{product_id: coke.id, qty: 2}, %{product_id: coke.id, qty: 3}]
    }

    assert {:ok, o} = Orders.create_order(attrs)
    assert [%{qty: 5}] = o.items
  end

  test "one unpaid order per phone", %{coke: coke} do
    assert {:ok, _} = Orders.create_order(order_attrs([{coke, 1}]))
    assert {:error, :pending_order} = Orders.create_order(order_attrs([{coke, 1}]))
  end

  test "ordering pause blocks new orders", %{coke: coke} do
    Settings.pause_ordering(true)
    assert {:error, :ordering_paused} = Orders.create_order(order_attrs([{coke, 1}]))
    Settings.pause_ordering(false)
    assert {:ok, _} = Orders.create_order(order_attrs([{coke, 1}]))
  end

  test "concurrent buyers never oversell the last bottle" do
    last = product(%{stock: 1})

    results =
      1..8
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), self())
          Orders.create_order(order_attrs([{last, 1}], %{payer_phone: unique_phone()}))
        end)
      end)
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert stock(last) == 0
  end

  test "legal transitions stamp times; illegal ones are refused", %{coke: coke} do
    {:ok, o} = Orders.create_order(order_attrs([{coke, 1}]))

    assert {:error, {:illegal_transition, :pending_payment, :ready}} =
             Orders.transition(o.id, :ready)

    assert {:ok, o} = Orders.transition(o.id, :paid, %{mpesa_receipt: "ABC123XYZ"})
    assert o.paid_at && o.mpesa_receipt == "ABC123XYZ"
    assert {:ok, _} = Orders.transition(o.id, :preparing)
    assert {:ok, o} = Orders.transition(o.id, :ready)
    assert o.ready_at
    assert {:ok, o} = Orders.transition(o.id, :completed)
    assert o.completed_at
    assert {:error, {:illegal_transition, :completed, :paid}} = Orders.transition(o.id, :paid)
  end

  test "cancel and expiry release reserved stock", %{gin: gin} do
    {:ok, o} = Orders.create_order(order_attrs([{gin, 2}]))
    assert stock(gin) == 3
    {:ok, _} = Orders.cancel(o.id)
    assert stock(gin) == 5

    {:ok, o2} = Orders.create_order(order_attrs([{gin, 3}]))
    assert stock(gin) == 2
    past = DateTime.add(DateTime.utc_now(), 3600)
    assert Orders.expire_due(past) == 1
    assert Orders.get_order(o2.id).status == :expired
    assert stock(gin) == 5
  end

  test "paid orders keep their stock; stock is not released twice", %{gin: gin} do
    {:ok, o} = Orders.create_order(order_attrs([{gin, 2}]))
    {:ok, _} = Orders.mark_paid(o.id, "RCPT1")
    assert stock(gin) == 3
    assert {:error, {:illegal_transition, :paid, :cancelled}} = Orders.cancel(o.id)
    assert stock(gin) == 3
  end

  test "mark_paid is idempotent for a repeated receipt", %{coke: coke} do
    {:ok, o} = Orders.create_order(order_attrs([{coke, 1}]))
    assert {:ok, a} = Orders.mark_paid(o.id, "RCPT2")
    assert {:ok, b} = Orders.mark_paid(o.id, "RCPT2")
    assert a.paid_at == b.paid_at
  end

  test "pickup codes are unique among live orders" do
    p = product(%{})

    codes =
      for _ <- 1..30 do
        {:ok, o} = Orders.create_order(order_attrs([{p, 1}], %{payer_phone: unique_phone()}))
        o.pickup_code
      end

    assert length(Enum.uniq(codes)) == 30
  end

  describe "serving: claim, release, deliver, lookup" do
    setup %{coke: coke} do
      {:ok, o} = Orders.create_order(order_attrs([{coke, 1}], %{payer_phone: unique_phone()}))
      {:ok, o} = Orders.mark_paid(o.id, "RKL1A2B3C9")
      {:ok, order: o}
    end

    test "first claim wins, same name is a no-op, another name is told who has it", %{order: o} do
      assert {:ok, %{claimed_by_name: "Amina"}} = Orders.claim(o.id, "  Amina ")
      assert {:ok, %{claimed_by_name: "Amina"}} = Orders.claim(o.id, "amina")
      assert {:error, {:claimed, "Amina"}} = Orders.claim(o.id, "Brian")
      assert {:error, :name_required} = Orders.claim(o.id, "   ")
    end

    test "release hands it back; only open orders can be claimed", %{order: o} do
      {:ok, _} = Orders.claim(o.id, "Amina")
      assert {:ok, %{claimed_by_name: nil}} = Orders.release(o.id)
      assert {:ok, %{claimed_by_name: "Brian"}} = Orders.claim(o.id, "Brian")
      {:ok, _} = Orders.deliver(o.id)
      assert {:error, {:not_open, :completed}} = Orders.claim(o.id, "Amina")
      assert {:error, :not_found} = Orders.claim(Ecto.UUID.generate(), "Amina")
    end

    test "deliver works from paid (the bar may not use the app) and from ready, once", %{order: o} do
      assert {:ok, %{status: :completed, completed_at: t}} = Orders.deliver(o.id)
      assert t
      assert {:error, {:illegal_transition, :completed, :completed}} = Orders.deliver(o.id)
    end

    test "unpaid orders cannot be delivered or claimed", %{coke: coke} do
      {:ok, u} = Orders.create_order(order_attrs([{coke, 1}], %{payer_phone: unique_phone()}))
      assert {:error, {:illegal_transition, :pending_payment, :completed}} = Orders.deliver(u.id)
      assert {:error, {:not_open, :pending_payment}} = Orders.claim(u.id, "Amina")
    end

    test "lookup by pickup code or the end of the M-Pesa code, case-insensitive, 4+ chars", %{
      order: o
    } do
      assert [%{id: id}] = Orders.lookup(String.downcase(o.pickup_code))
      assert id == o.id
      assert [%{id: ^id}] = Orders.lookup("a2b3c9")
      assert [%{id: ^id}] = Orders.lookup(" RKL1A2B3C9 ")
      assert Orders.lookup("B3C") == []
      assert Orders.lookup("ZZZZ") == []
      assert Orders.lookup("%%%%") == []
    end
  end
end
