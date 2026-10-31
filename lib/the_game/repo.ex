defmodule TheGame.Repo do
  use Ecto.Repo,
    otp_app: :the_game,
    adapter: Ecto.Adapters.Postgres
end
