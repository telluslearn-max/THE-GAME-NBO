defmodule TheGame.Repo.Migrations.OrderClaims do
  use Ecto.Migration

  # "I've got this one": which waiter is serving an order. A typed name, not an account, so the
  # existing shared staff login and the waiters' routine stay exactly as they are.
  def change do
    alter table(:orders) do
      add :claimed_by_name, :string
      add :claimed_at, :utc_datetime
    end
  end
end
