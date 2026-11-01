defmodule TheGameWeb.HealthController do
  use TheGameWeb, :controller

  @doc "Liveness + database check for the proxy and the container runtime."
  def show(conn, _params) do
    case Ecto.Adapters.SQL.query(TheGame.Repo, "select 1", []) do
      {:ok, _} -> conn |> put_resp_header("cache-control", "no-store") |> text("ok")
      _ -> conn |> put_status(503) |> text("database unavailable")
    end
  end
end
