defmodule TheGameWeb.History do
  @moduledoc """
  The visitor's order ids, kept in a signed, HttpOnly, one-year cookie (max 30).
  There are no accounts: possession of the order's UUID (an unguessable capability) plus
  this cookie is how a customer finds their orders again.
  """
  import Plug.Conn

  @cookie "tg_orders"
  @max 30
  @opts [sign: true, http_only: true, same_site: "Lax", max_age: 60 * 60 * 24 * 365]

  def ids(conn) do
    conn = fetch_cookies(conn, signed: [@cookie])

    case conn.cookies[@cookie] do
      v when is_binary(v) and v != "" ->
        v |> String.split(",", trim: true) |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1)))

      _ ->
        []
    end
  end

  def add(conn, id) do
    new = Enum.take(Enum.uniq([id | ids(conn)]), @max)

    put_resp_cookie(
      conn,
      @cookie,
      Enum.join(new, ","),
      Keyword.put(@opts, :secure, secure?(conn))
    )
  end

  def member?(conn, id), do: id in ids(conn)

  defp secure?(conn), do: conn.scheme == :https
end
