defmodule TheGame.Bookings.Booking do
  @moduledoc """
  A booking request. `kind` decides which fields are asked for and required:

    * `:table`  a table for 1 to 9 (online reservation)
    * `:group`  10 or more guests (staff quote a deposit and minimum spend by phone)
    * `:event`  birthday, corporate party, afterparty, graduation or other
    * `:collab` a brand or creator proposing a collaboration (no date, no party)
    * `:vip`    the VIP experience

  Every request starts `:new`; staff move it along. Nothing is confirmed until staff say so.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias TheGame.Phone

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @kinds ~w(table group event collab vip)a
  @statuses ~w(new contacted confirmed declined closed)a
  @event_types ~w(birthday corporate_party afterparty graduation other)a
  @seatings ~w(any indoor outdoor)a
  @vip_options ~w(reserved_table bottle_service advise_me)a
  @collab_types ~w(brand creator)a

  def kinds, do: @kinds
  def statuses, do: @statuses
  def event_types, do: @event_types
  def seatings, do: @seatings
  def vip_options, do: @vip_options
  def collab_types, do: @collab_types

  schema "bookings" do
    field :ref, :string
    field :kind, Ecto.Enum, values: @kinds
    field :status, Ecto.Enum, values: @statuses, default: :new
    field :name, :string
    field :phone, :string
    field :email, :string
    field :party_size, :integer
    field :on_date, :date
    field :at_time, :time
    field :event_type, Ecto.Enum, values: @event_types
    field :seating, Ecto.Enum, values: @seatings
    field :vip_option, Ecto.Enum, values: @vip_options
    field :org, :string
    field :collab_type, Ecto.Enum, values: @collab_types
    field :budget, :string
    field :message, :string
    field :staff_note, :string
    timestamps()
  end

  @cast ~w(name phone email party_size on_date at_time event_type seating vip_option org
           collab_type budget message)a

  @doc "Validate a public submission. `today` is the EAT calendar date."
  def changeset(kind, attrs, today) when kind in @kinds do
    %__MODULE__{kind: kind}
    |> cast(attrs, @cast)
    |> update_change(:name, &String.trim/1)
    |> update_change(:email, &String.downcase(String.trim(&1)))
    |> validate_required([:name, :phone], message: "is needed")
    |> validate_length(:name, max: 80)
    |> validate_length(:email, max: 120)
    |> validate_length(:org, max: 100)
    |> validate_length(:budget, max: 60)
    |> validate_length(:message, max: 1500)
    |> normalize_phone()
    |> validate_email()
    |> kind_rules(kind, today)
    |> keep_only(kind)
  end

  defp normalize_phone(cs) do
    case fetch_change(cs, :phone) do
      {:ok, raw} ->
        case Phone.normalize(raw) do
          {:ok, p} -> put_change(cs, :phone, p)
          :error -> add_error(cs, :phone, "needs a Kenyan mobile number, like 0712 345 678")
        end

      :error ->
        cs
    end
  end

  defp validate_email(cs) do
    case get_change(cs, :email) do
      nil ->
        cs

      "" ->
        delete_change(cs, :email)

      _ ->
        validate_format(cs, :email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "doesn’t look right")
    end
  end

  defp kind_rules(cs, :table, today) do
    cs
    |> validate_required([:party_size, :on_date, :at_time], message: "is needed")
    |> validate_number(:party_size,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 9,
      message: "is 1 to 9 here. For 10 or more, use Large groups"
    )
    |> future_date(today)
  end

  defp kind_rules(cs, :group, today) do
    cs
    |> validate_required([:party_size, :on_date, :at_time], message: "is needed")
    |> validate_number(:party_size,
      greater_than_or_equal_to: 10,
      less_than_or_equal_to: 300,
      message: "is 10 to 300 for a group"
    )
    |> future_date(today)
  end

  defp kind_rules(cs, :event, today) do
    cs
    |> validate_required([:event_type, :party_size, :on_date], message: "is needed")
    |> validate_number(:party_size,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 1000,
      message: "is 1 to 1000"
    )
    |> future_date(today)
  end

  defp kind_rules(cs, :vip, today) do
    cs
    |> validate_required([:vip_option, :party_size, :on_date], message: "is needed")
    |> validate_number(:party_size,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 50,
      message: "is 1 to 50"
    )
    |> future_date(today)
  end

  defp kind_rules(cs, :collab, _today) do
    cs
    |> validate_required([:collab_type, :org, :email, :message], message: "is needed")
    |> validate_length(:message,
      min: 20,
      message: "needs a little more: what do you have in mind?"
    )
  end

  defp future_date(cs, today) do
    validate_change(cs, :on_date, fn :on_date, d ->
      cond do
        Date.compare(d, today) == :lt -> [on_date: "can’t be in the past"]
        Date.diff(d, today) > 365 -> [on_date: "is too far ahead. Pick a date within a year"]
        true -> []
      end
    end)
  end

  # A request only keeps the fields its kind asks for, so a crafted post can't smuggle extras in.
  @keep %{
    table: ~w(party_size on_date at_time seating message)a,
    group: ~w(party_size on_date at_time event_type seating budget message)a,
    event: ~w(party_size on_date at_time event_type budget message)a,
    vip: ~w(party_size on_date at_time vip_option message)a,
    collab: ~w(collab_type org budget message)a
  }

  defp keep_only(cs, kind) do
    drop = (@cast -- ~w(name phone email)a) -- Map.fetch!(@keep, kind)
    Enum.reduce(drop, cs, &delete_change(&2, &1))
  end
end
