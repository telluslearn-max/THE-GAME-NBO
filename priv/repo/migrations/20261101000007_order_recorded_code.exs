defmodule TheGame.Repo.Migrations.OrderRecordedCode do
  use Ecto.Migration

  # What the waiter wrote down from the client's phone (last 4 of the M-Pesa code + time paid).
  # Stored as typed. The counter compares it with the order's actual code by eye.
  def change do
    alter table(:orders) do
      add :recorded_code, :string
      add :recorded_time, :string
    end
  end
end
