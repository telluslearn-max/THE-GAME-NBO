defmodule Mix.Tasks.TheGame.Staff.Create do
  @shortdoc "Create a staff login: mix the_game.staff.create EMAIL PASSWORD [admin]"
  use Mix.Task

  @impl true
  def run([email, password]), do: create(email, password, :staff)
  def run([email, password, "admin"]), do: create(email, password, :admin)

  def run(_),
    do: Mix.raise("usage: mix the_game.staff.create EMAIL PASSWORD [admin] (password 8+ chars)")

  defp create(email, password, role) do
    Mix.Task.run("app.start")

    case TheGame.Staff.create_user(%{email: email, password: password, role: role}) do
      {:ok, u} -> Mix.shell().info("created #{u.role} #{u.email}")
      {:error, cs} -> Mix.raise("could not create staff: #{inspect(cs.errors)}")
    end
  end
end
