defmodule TheGame.Release do
  @moduledoc """
  Release tasks, run without Mix:

      bin/the_game eval "TheGame.Release.migrate()"
      bin/the_game eval 'TheGame.Release.create_staff("owner@example.com", "a long passphrase")'
  """
  @app :the_game

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def create_staff(email, password) do
    load_app()

    {:ok, res, _} =
      Ecto.Migrator.with_repo(TheGame.Repo, fn _ ->
        TheGame.Staff.create_user(%{email: email, password: password})
      end)

    case res do
      {:ok, u} -> IO.puts("created staff #{u.email}")
      {:error, cs} -> IO.inspect(cs.errors, label: "could not create staff")
    end
  end

  @doc "Load the starter menu (only when the menu is empty). Replace it through the staff app."
  def seed do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(TheGame.Repo, fn _ ->
        Code.eval_file(Application.app_dir(@app, "priv/repo/seeds.exs"))
      end)

    IO.puts("seed done")
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
  defp load_app, do: Application.load(@app)
end
