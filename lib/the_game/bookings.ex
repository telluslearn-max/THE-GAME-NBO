defmodule TheGame.Bookings do
  @moduledoc """
  Booking requests: table reservations, large groups, events, collabs and the VIP experience.

  A request is a promise to be called, not a held table: staff confirm by phone or WhatsApp,
  and the customer is told so. No money moves here (a deposit, where one is agreed, is taken
  over the existing M-Pesa routine).
  """
  import Ecto.Query
  alias TheGame.Repo
  alias TheGame.Bookings.Booking

  @ref_chars ~c"23456789ABCDEFGHJKMNPQRSTUVWXYZ"
  @max_per_phone_per_hour 5

  def kinds, do: Booking.kinds()

  @doc "EAT (UTC+3) calendar date, the venue's own."
  def today, do: DateTime.utc_now() |> DateTime.add(3 * 3600) |> DateTime.to_date()

  @spec change(atom, map) :: Ecto.Changeset.t()
  def change(kind, attrs \\ %{}), do: Booking.changeset(kind, attrs, today())

  @doc """
  Create a request. Idempotent against double taps: the same phone asking for the same kind and
  date within ten minutes returns the request already made. A phone is capped per hour.
  """
  @spec create(atom, map) :: {:ok, Booking.t()} | {:error, Ecto.Changeset.t() | :too_many}
  def create(kind, attrs) do
    cs = change(kind, attrs)

    with {:ok, b} <- Ecto.Changeset.apply_action(cs, :insert) do
      case recent_duplicate(b) do
        %Booking{} = dup -> {:ok, dup}
        nil -> insert(cs, b.phone)
      end
    end
  end

  defp insert(cs, phone) do
    if recent_count(phone) >= @max_per_phone_per_hour do
      {:error, :too_many}
    else
      case Repo.insert(Ecto.Changeset.put_change(cs, :ref, gen_ref())) do
        {:ok, b} ->
          broadcast({:booking, b})
          {:ok, b}

        {:error, %{errors: [ref: _]}} ->
          insert(cs, phone)

        other ->
          other
      end
    end
  end

  defp recent_duplicate(%Booking{kind: kind, phone: phone, on_date: d}) do
    since = DateTime.add(DateTime.utc_now(), -600)

    q =
      from b in Booking,
        where: b.phone == ^phone and b.kind == ^kind and b.inserted_at > ^since,
        order_by: [desc: b.inserted_at],
        limit: 1

    q = if d, do: where(q, [b], b.on_date == ^d), else: where(q, [b], is_nil(b.on_date))
    Repo.one(q)
  end

  defp recent_count(phone) do
    since = DateTime.add(DateTime.utc_now(), -3600)

    Repo.aggregate(
      from(b in Booking, where: b.phone == ^phone and b.inserted_at > ^since),
      :count
    )
  end

  defp gen_ref, do: for(_ <- 1..6, into: "", do: <<Enum.random(@ref_chars)>>)

  def get_by_ref(ref) when is_binary(ref), do: Repo.get_by(Booking, ref: String.upcase(ref))

  @doc "Requests staff still need to act on or that are coming up, soonest first."
  def list_open do
    t = today()

    Repo.all(
      from b in Booking,
        where:
          b.status in [:new, :contacted] or
            (b.status == :confirmed and (is_nil(b.on_date) or b.on_date >= ^t)),
        order_by: [
          asc: fragment("case ? when 'new' then 0 when 'contacted' then 1 else 2 end", b.status),
          asc: b.on_date,
          asc: b.inserted_at
        ]
    )
  end

  def count_new, do: Repo.aggregate(from(b in Booking, where: b.status == :new), :count)

  @doc "Move a request to a new status. Only the staff statuses are accepted."
  def set_status(id, status) when status in [:contacted, :confirmed, :declined, :closed] do
    case Repo.get(Booking, id) do
      nil ->
        {:error, :not_found}

      b ->
        {:ok, b} = b |> Ecto.Changeset.change(status: status) |> Repo.update()
        broadcast({:booking_updated, b})
        {:ok, b}
    end
  end

  def subscribe, do: Phoenix.PubSub.subscribe(TheGame.PubSub, "bookings")
  defp broadcast(msg), do: Phoenix.PubSub.broadcast(TheGame.PubSub, "bookings", msg)
end
