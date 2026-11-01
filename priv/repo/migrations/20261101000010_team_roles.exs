defmodule TheGame.Repo.Migrations.TeamRoles do
  use Ecto.Migration

  # People get a display name, and a third role: "waiter" sees the board only.
  def up do
    alter table(:staff_users) do
      add :name, :string, null: false, default: ""
    end

    drop constraint(:staff_users, :role_values)
    create constraint(:staff_users, :role_values, check: "role in ('staff','admin','waiter')")
  end

  def down do
    drop constraint(:staff_users, :role_values)
    create constraint(:staff_users, :role_values, check: "role in ('staff','admin')")

    alter table(:staff_users) do
      remove :name
    end
  end
end
