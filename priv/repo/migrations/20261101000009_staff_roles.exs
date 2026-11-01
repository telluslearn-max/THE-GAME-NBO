defmodule TheGame.Repo.Migrations.StaffRoles do
  use Ecto.Migration

  # Two kinds of login. "staff" is the floor login everyone uses today (unchanged). "admin" is
  # the owner's, and additionally sees the Insights page.
  def change do
    alter table(:staff_users) do
      add :role, :string, null: false, default: "staff"
    end

    create constraint(:staff_users, :role_values, check: "role in ('staff','admin')")
  end
end
