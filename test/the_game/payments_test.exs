defmodule TheGame.PaymentsTest do
  use TheGame.DataCase, async: false
  import TheGame.Fixtures
  alias TheGame.{Orders, Payments, Repo}
  alias TheGame.Catalog.Product
  alias TheGame.Mpesa.Fake
  alias TheGame.Payments.{Payment, Review}

  setup do
    Application.put_env(:the_game, :stk_cooldown_seconds, 0)
    gin = product(%{price_cents: 125_000, stock: 5})
    {:ok, order} = Orders.create_order(order_attrs([{gin, 2}]))
    {:ok, gin: gin, order: order}
  end

  defp stock(p), do: Repo.get!(Product, p.id).stock
  defp status(o), do: Orders.get_order!(o.id).status
  defp reviews(o), do: Repo.all(from r in Review, where: r.order_id == ^o.id)

  defp sent!(order) do
    {:ok, p} = Payments.request_stk(order.id)
    assert p.status == :sent and is_binary(p.checkout_request_id)
    p
  end

  describe "requesting a prompt" do
    test "creates a sent payment for the right phone and whole-shilling amount", %{order: o} do
      p = sent!(o)
      assert p.phone == "254712345678"
      assert p.amount_cents == 250_000
    end

    test "cooldown blocks a second prompt and says how long", %{order: o} do
      Application.put_env(:the_game, :stk_cooldown_seconds, 60)
      sent!(o)
      assert {:error, {:cooldown, n}} = Payments.request_stk(o.id)
      assert n in 58..60
    end

    test "after the cooldown, an unresolved prompt must be checked before another is sent", %{
      order: o
    } do
      sent!(o)
      assert {:error, :unresolved} = Payments.request_stk(o.id)
      assert {:ok, :pending} = Payments.check(o.id)
      assert {:error, :unresolved} = Payments.request_stk(o.id)
    end

    test "a resolved-as-cancelled prompt unlocks a retry", %{order: o} do
      p = sent!(o)
      Fake.complete(p.checkout_request_id, :cancelled, deliver: false)
      assert {:ok, :failed} = Payments.check(o.id)
      assert {:ok, %Payment{status: :sent}} = Payments.request_stk(o.id)
    end

    test "gateway failure is recorded, reported, and retryable", %{order: o} do
      Fake.fail_next()
      assert {:error, :gateway} = Payments.request_stk(o.id)
      assert %Payment{status: :failed} = Payments.latest_payment(o.id)
      assert {:ok, %Payment{status: :sent}} = Payments.request_stk(o.id)
    end

    test "cannot prompt for expired, cancelled, or already-paid orders", %{order: o} do
      p = sent!(o)
      Fake.complete(p.checkout_request_id, :success)
      assert {:error, :already_paid} = Payments.request_stk(o.id)

      {:ok, o2} =
        Orders.create_order(order_attrs([{product(), 1}], %{payer_phone: unique_phone()}))

      Orders.cancel(o2.id)
      assert {:error, :not_payable} = Payments.request_stk(o2.id)
      assert {:error, :not_found} = Payments.request_stk(Ecto.UUID.generate())
    end
  end

  describe "callbacks" do
    test "success marks the order paid with the receipt and keeps stock", %{order: o, gin: gin} do
      p = sent!(o)
      Fake.complete(p.checkout_request_id, :success, receipt: "RCPT100")
      o = Orders.get_order!(o.id)
      assert o.status == :paid and o.mpesa_receipt == "RCPT100" and o.paid_at
      assert stock(gin) == 3
      assert Payments.latest_payment(o.id).status == :success
      assert reviews(o) == []
    end

    test "Safaricom's TransactionDate (EAT) becomes the order's actual payment time", %{order: o} do
      p = sent!(o)

      payload =
        Fake.callback_payload(
          p.checkout_request_id,
          %{phone: "254712345678"},
          0,
          "ok",
          "TD123456AB",
          2500
        )

      # 16:52:10 East Africa Time == 13:52:10 UTC
      payload =
        put_in(
          payload,
          ["Body", "stkCallback", "CallbackMetadata", "Item"],
          Enum.map(payload["Body"]["stkCallback"]["CallbackMetadata"]["Item"], fn
            %{"Name" => "TransactionDate"} = i -> %{i | "Value" => 20_261_101_165_210}
            i -> i
          end)
        )

      Payments.handle_callback(payload)
      assert %{mpesa_paid_at: t} = Orders.get_order!(o.id)
      assert DateTime.to_iso8601(t) == "2026-11-01T13:52:10Z"
    end

    test "replaying the same callback changes nothing", %{order: o} do
      p = sent!(o)
      payload = Fake.complete(p.checkout_request_id, :success, receipt: "RCPT101")
      before = Orders.get_order!(o.id)
      assert {:ok, :noop} = Payments.handle_callback(payload)
      assert {:ok, :noop} = Payments.handle_callback(payload)
      assert Orders.get_order!(o.id).paid_at == before.paid_at
      assert reviews(o) == []
    end

    test "unknown checkout ids are ignored, not trusted", %{order: o} do
      payload =
        Fake.callback_payload("ws_CO_FORGED", %{phone: "254700000000"}, 0, "ok", "FORGED1", 2500)

      assert {:error, :unknown_payment} = Payments.handle_callback(payload)
      assert status(o) == :pending_payment
    end

    test "malformed bodies are rejected" do
      assert {:error, :malformed} = Payments.handle_callback(%{"nope" => 1})
    end

    test "cancelled / timed out / failed leave the order payable", %{order: o} do
      for outcome <- [:cancelled, :timeout, :failed] do
        p = sent!(o)
        Fake.complete(p.checkout_request_id, outcome)
        assert status(o) == :pending_payment
        assert Payments.latest_payment(o.id).status == outcome
      end
    end

    test "underpayment flags the order and queues a short review", %{order: o} do
      p = sent!(o)
      Fake.complete(p.checkout_request_id, :success, amount: 1000, receipt: "SHORT1")
      assert status(o) == :flagged
      assert [%Review{kind: :short, amount_cents: 100_000, status: :pending}] = reviews(o)
    end

    test "overpayment pays the order and queues an extra review", %{order: o} do
      p = sent!(o)
      Fake.complete(p.checkout_request_id, :success, amount: 3000, receipt: "OVER1")
      assert status(o) == :paid
      assert [%Review{kind: :extra, amount_cents: 300_000}] = reviews(o)
    end

    test "a payment after expiry is never lost: order flagged, stock retaken, review queued", %{
      order: o,
      gin: gin
    } do
      p = sent!(o)
      Orders.expire_due(DateTime.add(DateTime.utc_now(), 3600))
      assert status(o) == :expired and stock(gin) == 5

      Fake.complete(p.checkout_request_id, :success, receipt: "LATE1")
      assert status(o) == :flagged
      assert stock(gin) == 3
      assert [%Review{kind: :late, mpesa_receipt: "LATE1"}] = reviews(o)
    end

    test "a payment after the customer cancelled is also held for review", %{order: o} do
      p = sent!(o)
      Orders.cancel(o.id)
      Fake.complete(p.checkout_request_id, :success, receipt: "CANC1")
      assert status(o) == :flagged
      assert [%Review{kind: :late}] = reviews(o)
    end

    test "a second successful payment for a paid order is queued as extra", %{order: o} do
      p1 = sent!(o)
      Fake.complete(p1.checkout_request_id, :timeout)
      p2 = sent!(o)
      Fake.complete(p2.checkout_request_id, :success, receipt: "PAID2")
      # the first prompt turns out to have been paid after all
      Payments.handle_callback(
        Fake.callback_payload(
          p1.checkout_request_id,
          %{phone: "254712345678"},
          0,
          "ok",
          "PAID1",
          2500
        )
      )

      assert status(o) == :paid
      assert [%Review{kind: :extra, mpesa_receipt: "PAID1"}] = reviews(o)
    end
  end

  describe "staff resolution" do
    setup %{order: o} do
      p = sent!(o)
      Orders.expire_due(DateTime.add(DateTime.utc_now(), 3600))
      Fake.complete(p.checkout_request_id, :success, receipt: "RES1")
      [review] = reviews(o)
      {:ok, review: review}
    end

    test "refund closes the order and releases stock", %{order: o, review: r, gin: gin} do
      assert {:ok, %Review{status: :refunded}} = Payments.resolve_review(r.id, :refunded)
      assert status(o) == :closed
      assert stock(gin) == 5
    end

    test "honouring sends the order to the bar", %{order: o, review: r, gin: gin} do
      assert {:ok, %Review{status: :honored}} = Payments.resolve_review(r.id, :honored)
      assert status(o) == :preparing
      assert Orders.get_order!(o.id).mpesa_receipt == "RES1"
      assert stock(gin) == 3
    end

    test "a review can only be resolved once", %{review: r} do
      assert {:ok, _} = Payments.resolve_review(r.id, :refunded)
      assert {:error, :already_resolved} = Payments.resolve_review(r.id, :honored)
    end
  end

  describe "STK query and reconciliation" do
    test "check() settles a prompt whose callback never arrived", %{order: o} do
      p = sent!(o)
      Fake.complete(p.checkout_request_id, :success, deliver: false, receipt: "QRY1")
      assert status(o) == :pending_payment
      assert {:ok, :paid} = Payments.check(o.id)
      assert status(o) == :paid
      assert Orders.get_order!(o.id).mpesa_receipt == "QRY1"
    end

    test "reconcile() sweeps old unresolved prompts", %{order: o} do
      p = sent!(o)
      Fake.complete(p.checkout_request_id, :success, deliver: false, receipt: "RCN1")
      assert Payments.reconcile(0) == 1
      assert status(o) == :paid
      assert Payments.reconcile(0) == 0
    end

    test "a callback racing the query settles exactly once", %{order: o} do
      p = sent!(o)
      payload = Fake.complete(p.checkout_request_id, :success, deliver: false, receipt: "RACE1")

      tasks =
        for i <- 1..6 do
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), self())
            if rem(i, 2) == 0, do: Payments.handle_callback(payload), else: Payments.check(o.id)
          end)
        end

      Enum.each(tasks, &Task.await/1)
      assert status(o) == :paid
      assert reviews(o) == []
      assert Repo.aggregate(from(p in Payment, where: p.mpesa_receipt == "RACE1"), :count) == 1
    end
  end
end
