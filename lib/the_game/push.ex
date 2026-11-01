defmodule TheGame.Push do
  @moduledoc """
  "Your drinks are ready" Web Push. Strictly best-effort and secondary: the page itself chimes
  and vibrates, and the order is never affected by a push failure.

  Security: the endpoint URL comes from the client and our server will POST to it, so only
  the real browser push services are accepted (no SSRF to internal addresses).
  """
  import Ecto.Query
  require Logger
  alias TheGame.Push.Subscription
  alias TheGame.Repo

  @max_per_order 3
  @allowed_suffixes ~w(.googleapis.com .push.services.mozilla.com .push.apple.com .notify.windows.com)

  @callback deliver(subscription_json :: String.t(), payload_json :: String.t()) ::
              :ok | {:error, :expired} | {:error, term}

  def sender, do: Application.get_env(:the_game, :push_sender, TheGame.Push.WebPush)
  def public_key, do: Application.get_env(:the_game, :vapid_public_key)
  def enabled?, do: is_binary(public_key())

  @spec subscribe(String.t(), map) :: {:ok, Subscription.t()} | {:error, :invalid | :too_many}
  def subscribe(order_id, %{"endpoint" => ep, "keys" => %{"p256dh" => k, "auth" => a}})
      when is_binary(ep) and is_binary(k) and is_binary(a) do
    cond do
      not allowed_endpoint?(ep) ->
        {:error, :invalid}

      not (b64url?(k) and b64url?(a)) ->
        {:error, :invalid}

      Repo.exists?(from s in Subscription, where: s.order_id == ^order_id and s.endpoint == ^ep) ->
        {:ok, Repo.get_by!(Subscription, order_id: order_id, endpoint: ep)}

      Repo.aggregate(from(s in Subscription, where: s.order_id == ^order_id), :count) >=
          @max_per_order ->
        {:error, :too_many}

      true ->
        Repo.insert(%Subscription{order_id: order_id, endpoint: ep, p256dh: k, auth: a})
    end
  end

  def subscribe(_, _), do: {:error, :invalid}

  def subscribed?(order_id),
    do: Repo.exists?(from s in Subscription, where: s.order_id == ^order_id)

  @doc false
  def allowed_endpoint?(ep) do
    case URI.parse(ep) do
      %URI{scheme: "https", host: host, port: 443} when is_binary(host) ->
        Enum.any?(@allowed_suffixes, &String.ends_with?(host, &1))

      _ ->
        false
    end
  end

  defp b64url?(s),
    do: match?({:ok, _}, Base.url_decode64(s, padding: false)) and byte_size(s) in 8..200

  @doc "Fire-and-forget: tell every subscribed device of this order that it is ready."
  def notify_ready(%{id: order_id, pickup_code: code}) do
    if enabled?() or sender() != TheGame.Push.WebPush do
      Task.Supervisor.start_child(TheGame.TaskSupervisor, fn -> send_ready(order_id, code) end)
    end

    :ok
  end

  @doc false
  def send_ready(order_id, code) do
    payload =
      Jason.encode!(%{
        title: "Your drinks are ready",
        body: "Code #{code}. Collect at the bar.",
        url: "/order/" <> order_id
      })

    for sub <- Repo.all(from s in Subscription, where: s.order_id == ^order_id) do
      json = Jason.encode!(%{endpoint: sub.endpoint, keys: %{p256dh: sub.p256dh, auth: sub.auth}})

      case safe(fn -> sender().deliver(json, payload) end) do
        :ok -> :ok
        {:error, :expired} -> Repo.delete(sub)
        other -> Logger.warning("push failed for order #{order_id}: #{inspect(other)}")
      end
    end

    :ok
  end

  defp safe(fun) do
    fun.()
  rescue
    e -> {:error, {:exception, Exception.message(e)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
