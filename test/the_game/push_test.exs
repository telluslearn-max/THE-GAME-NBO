defmodule TheGame.PushTest do
  use TheGame.DataCase, async: false
  import TheGame.Fixtures
  alias TheGame.{Orders, Push, Repo}
  alias TheGame.Push.{Memory, Subscription}

  @ep "https://fcm.googleapis.com/fcm/send/abc123"
  @keys %{
    "p256dh" =>
      "BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlUls0VJXg7A8u-Ts1XbjhazAkj7I99e8QcYP7DkM",
    "auth" => "tBHItJI5svbpez7KI4CCXg"
  }

  setup do
    Memory.reset()
    {:ok, order} = Orders.create_order(order_attrs([{product(), 1}]))
    {:ok, order: order}
  end

  test "only real push services are accepted (no SSRF)", %{order: o} do
    for bad <- [
          "http://fcm.googleapis.com/x",
          "https://127.0.0.1/x",
          "https://localhost/x",
          "https://169.254.169.254/latest/meta-data",
          "https://fcm.googleapis.com.evil.com/x",
          "https://evilgoogleapis.com/x",
          "https://fcm.googleapis.com:8443/x",
          "https://internal.service.local/x",
          "ftp://fcm.googleapis.com/x"
        ] do
      assert {:error, :invalid} = Push.subscribe(o.id, %{"endpoint" => bad, "keys" => @keys}), bad
    end

    for good <- [
          @ep,
          "https://updates.push.services.mozilla.com/wpush/v2/abc",
          "https://web.push.apple.com/QGxyz",
          "https://wns2-par02p.notify.windows.com/w/?token=abc"
        ] do
      {:ok, fresh} =
        Orders.create_order(order_attrs([{product(), 1}], %{payer_phone: unique_phone()}))

      assert {:ok, _} = Push.subscribe(fresh.id, %{"endpoint" => good, "keys" => @keys}), good
    end
  end

  test "malformed subscriptions are rejected", %{order: o} do
    assert {:error, :invalid} = Push.subscribe(o.id, %{"endpoint" => @ep})

    assert {:error, :invalid} =
             Push.subscribe(o.id, %{
               "endpoint" => @ep,
               "keys" => %{"p256dh" => "!!!", "auth" => "x"}
             })

    assert {:error, :invalid} = Push.subscribe(o.id, "nope")
  end

  test "subscribing twice is idempotent and each order is capped", %{order: o} do
    {:ok, a} = Push.subscribe(o.id, %{"endpoint" => @ep, "keys" => @keys})
    {:ok, b} = Push.subscribe(o.id, %{"endpoint" => @ep, "keys" => @keys})
    assert a.id == b.id

    for n <- 1..2,
        do: {:ok, _} = Push.subscribe(o.id, %{"endpoint" => @ep <> "#{n}", "keys" => @keys})

    assert {:error, :too_many} =
             Push.subscribe(o.id, %{"endpoint" => @ep <> "x", "keys" => @keys})
  end

  test "ready sends one notification per device with the code and a link", %{order: o} do
    {:ok, _} = Push.subscribe(o.id, %{"endpoint" => @ep, "keys" => @keys})
    Orders.mark_paid(o.id, "PSH1")
    Orders.transition(o.id, :preparing)
    assert Memory.sent() == []

    {:ok, _} = Orders.transition(o.id, :ready)
    wait_for(fn -> length(Memory.sent()) == 1 end)
    [{sub, payload}] = Memory.sent()
    assert Jason.decode!(sub)["endpoint"] == @ep
    msg = Jason.decode!(payload)
    assert msg["title"] == "Your drinks are ready"
    assert msg["body"] =~ o.pickup_code
    assert msg["url"] == "/order/#{o.id}"
  end

  test "an expired subscription is removed and never blocks the order", %{order: o} do
    {:ok, _} = Push.subscribe(o.id, %{"endpoint" => @ep, "keys" => @keys})
    Memory.expire_next()
    Orders.mark_paid(o.id, "PSH2")
    {:ok, ready} = Orders.transition(o.id, :ready)
    assert ready.status == :ready
    wait_for(fn -> Repo.aggregate(Subscription, :count) == 0 end)
  end

  test "orders with no subscription just don't push", %{order: o} do
    Orders.mark_paid(o.id, "PSH3")
    {:ok, _} = Orders.transition(o.id, :ready)
    Process.sleep(50)
    assert Memory.sent() == []
  end

  defp wait_for(fun, tries \\ 40) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition not met in time")
      true -> Process.sleep(25) && wait_for(fun, tries - 1)
    end
  end
end
