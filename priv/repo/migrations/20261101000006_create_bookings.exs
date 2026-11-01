defmodule TheGame.Repo.Migrations.CreateBookings do
  use Ecto.Migration

  # Booking requests: table reservations, large groups, events, collabs and VIP. One table, one
  # shape: a request is something staff confirm by phone/WhatsApp, so nothing here holds money.
  def change do
    create table(:bookings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ref, :string, null: false
      add :kind, :string, null: false
      add :status, :string, null: false, default: "new"
      add :name, :string, null: false
      add :phone, :string, null: false
      add :email, :string
      add :party_size, :integer
      add :on_date, :date
      add :at_time, :time
      add :event_type, :string
      add :seating, :string
      add :vip_option, :string
      add :org, :string
      add :collab_type, :string
      add :budget, :string
      add :message, :text
      add :staff_note, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:bookings, [:ref])
    create index(:bookings, [:status, :on_date])
    create index(:bookings, [:phone, :inserted_at])
  end
end
