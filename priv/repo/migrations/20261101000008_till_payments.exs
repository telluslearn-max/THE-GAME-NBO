defmodule TheGame.Repo.Migrations.TillPayments do
  use Ecto.Migration

  # Most clients pay by typing the till number. Nothing tells the app, so staff confirm the
  # payment after the counter has matched the M-Pesa message on the POS. We keep who and when.
  def change do
    alter table(:orders) do
      add :payment_method, :string
      add :confirmed_by_name, :string
      add :confirmed_at, :utc_datetime
    end
  end
end
