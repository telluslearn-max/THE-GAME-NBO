defmodule TheGame.Push.WebPush do
  @moduledoc """
  Real sender via `web_push_elixir`. NOTE: that library encrypts with the legacy `aesgcm`
  content encoding. Verify delivery on real Android Chrome and iOS (installed PWA) before
  relying on it; the on-page alert and the staff board do not depend on push.
  """
  @behaviour TheGame.Push

  @impl true
  def deliver(subscription_json, payload_json) do
    case WebPushElixir.send_notification(subscription_json, payload_json,
           urgency: :high,
           ttl: 600,
           topic: "order-ready"
         ) do
      {:ok, _} -> :ok
      {:error, :expired} -> {:error, :expired}
      {:error, e} -> {:error, e}
    end
  end
end
