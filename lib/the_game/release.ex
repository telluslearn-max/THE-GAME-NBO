defmodule TheGame.Release do
  @moduledoc """
  Release tasks, run without Mix:

      bin/the_game eval "TheGame.Release.migrate()"
      bin/the_game eval 'TheGame.Release.create_staff("owner@example.com", "a long passphrase")'
  """
  import Ecto.Query, only: [from: 2]

  @app :the_game

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    bootstrap()
  end

  @doc """
  First-boot setup from the environment, so a hosted deploy needs no shell access:
  `STAFF_EMAIL` + `STAFF_PASSWORD` create the first staff login when none exists, and
  `SEED_MENU=true` loads the starter menu when the menu is empty. Both are no-ops afterwards.
  """
  def bootstrap do
    email = System.get_env("STAFF_EMAIL")
    password = System.get_env("STAFF_PASSWORD")
    seed? = System.get_env("SEED_MENU") in ~w(true 1)

    {:ok, _, _} =
      Ecto.Migrator.with_repo(TheGame.Repo, fn repo ->
        # STAFF_RESET_PASSWORD=true re-applies STAFF_PASSWORD to the STAFF_EMAIL account on boot
        # (how a hosted deploy changes a login without shell access). Remove the flag afterwards.
        if email && password && System.get_env("STAFF_RESET_PASSWORD") in ~w(true 1) &&
             repo.aggregate(TheGame.Staff.User, :count) > 0 do
          case TheGame.Staff.set_password(email, password) do
            {:ok, u} -> IO.puts("bootstrap: password reset for #{u.email}")
            other -> IO.inspect(other, label: "bootstrap: password NOT reset")
          end
        end

        # ADMIN_EMAIL + ADMIN_PASSWORD: the owner's login (sees the Insights page). Created once;
        # with STAFF_RESET_PASSWORD=true its password is re-applied on boot.
        admin_email = System.get_env("ADMIN_EMAIL")
        admin_password = System.get_env("ADMIN_PASSWORD")

        if admin_email && admin_password do
          case repo.get_by(TheGame.Staff.User, email: String.downcase(String.trim(admin_email))) do
            nil ->
              case TheGame.Staff.create_user(%{
                     email: admin_email,
                     password: admin_password,
                     role: :admin
                   }) do
                {:ok, u} -> IO.puts("bootstrap: created admin #{u.email}")
                {:error, cs} -> IO.inspect(cs.errors, label: "bootstrap: admin not created")
              end

            _existing ->
              if System.get_env("STAFF_RESET_PASSWORD") in ~w(true 1) do
                IO.inspect(TheGame.Staff.set_password(admin_email, admin_password) |> elem(0),
                  label: "bootstrap: admin password reset"
                )
              end
          end
        end

        if email && password &&
             repo.aggregate(from(u in TheGame.Staff.User, where: u.role == :staff), :count) == 0 do
          case TheGame.Staff.create_user(%{email: email, password: password}) do
            {:ok, u} -> IO.puts("bootstrap: created staff #{u.email}")
            {:error, cs} -> IO.inspect(cs.errors, label: "bootstrap: staff not created")
          end
        end

        if seed? and repo.aggregate(TheGame.Catalog.Category, :count) == 0 do
          Code.eval_file(Application.app_dir(@app, "priv/repo/seeds.exs"))
          IO.puts("bootstrap: starter menu loaded")
        end
      end)

    :ok
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
