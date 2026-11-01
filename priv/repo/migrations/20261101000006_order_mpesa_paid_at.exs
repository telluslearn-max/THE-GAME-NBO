defmodule TheGame.Repo.Migrations.OrderMpesaPaidAt do
  use Ecto.Migration

  # The payment time as Safaricom reports it (callback TransactionDate), which is what the
  # client's M-Pesa SMS shows. paid_at stays "when our server recorded it".
  def change do
    alter table(:orders) do
      add :mpesa_paid_at, :utc_datetime
    end
  end
end
