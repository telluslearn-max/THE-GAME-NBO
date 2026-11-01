defmodule TheGame.Repo.Migrations.PaymentsUsecTimestamps do
  use Ecto.Migration

  # "Latest payment for an order" decides whether a customer may be prompted again, so its
  # ordering must be unambiguous: second precision let two prompts tie.
  def change do
    alter table(:payments) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime
    end
  end
end
