defmodule TheGame.Repo.Migrations.CreateStaffUsers do
  use Ecto.Migration

  def change do
    create table(:staff_users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :password_hash, :string, null: false
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    create unique_index(:staff_users, [:email])
  end
end
