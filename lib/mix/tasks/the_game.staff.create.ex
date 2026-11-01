defmodule Mix.Tasks.TheGame.Staff.Create do
  @shortdoc "Create a staff login: mix the_game.staff.create EMAIL PASSWORD"
  use Mix.Task

  @impl true
  def run([email, password]) do
    Mix.Task.run("app.start")

    case TheGame.Staff.create_user(%{email: email, password: password}) do
      {:ok, u} -> Mix.shell().info("created staff #{u.email}")
      {:error, cs} -> Mix.raise("could not create staff: #{inspect(cs.errors)}")
    end
  end

  def run(_),
    do: Mix.raise("usage: mix the_game.staff.create EMAIL PASSWORD (password 8+ chars)")
end
