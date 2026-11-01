defmodule TheGameWeb.Plugs.Compress do
  @moduledoc """
  gzip for dynamic text responses, so the app is small on the wire even with no proxy in
  front (a proxy that compresses, like Caddy, skips anything already encoded). Also adds a
  strong ETag so an unchanged page costs a bodyless 304.
  """
  import Plug.Conn

  @types ~w(text/html application/json application/manifest+json image/svg+xml text/plain)
  @min 600

  def init(opts), do: opts

  def call(conn, _opts), do: register_before_send(conn, &finish/1)

  defp finish(%Plug.Conn{method: "GET", status: 200, state: :set} = conn) do
    with false <- has_encoding?(conn),
         true <- compressible?(conn),
         body when is_list(body) or is_binary(body) <- conn.resp_body do
      bin = IO.iodata_to_binary(body)
      etag = ~s("#{Base.url_encode64(:crypto.hash(:md5, bin), padding: false)}")

      cond do
        etag in get_req_header(conn, "if-none-match") ->
          conn
          |> put_resp_header("etag", etag)
          |> delete_resp_header("content-type")
          |> resp(304, "")

        byte_size(bin) >= @min and gzip?(conn) ->
          conn
          |> put_resp_header("etag", etag)
          |> put_resp_header("content-encoding", "gzip")
          |> prepend_vary()
          |> resp(200, :zlib.gzip(bin))

        true ->
          conn |> put_resp_header("etag", etag) |> prepend_vary()
      end
    else
      _ -> conn
    end
  end

  defp finish(conn), do: conn

  defp has_encoding?(conn), do: get_resp_header(conn, "content-encoding") != []

  defp compressible?(conn) do
    case get_resp_header(conn, "content-type") do
      [ct | _] -> Enum.any?(@types, &String.starts_with?(ct, &1))
      _ -> false
    end
  end

  defp gzip?(conn), do: Enum.any?(get_req_header(conn, "accept-encoding"), &(&1 =~ "gzip"))

  defp prepend_vary(conn), do: put_resp_header(conn, "vary", "accept-encoding")
end
