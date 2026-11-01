defmodule TheGameWeb.Plugs.Security do
  @moduledoc """
  Response hardening: a strict CSP (no inline script, no third parties), a tight
  Permissions-Policy, and, when the request arrived over HTTPS (directly or via a trusted proxy),
  HSTS plus the `Secure` flag on every cookie we set.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    host = conn.host

    csp =
      Enum.join(
        [
          "default-src 'self'",
          "script-src 'self'",
          "style-src 'self'",
          "img-src 'self' data:",
          "font-src 'self'",
          "connect-src 'self' wss://#{host} ws://#{host}",
          "manifest-src 'self'",
          "worker-src 'self'",
          "object-src 'none'",
          "base-uri 'self'",
          "form-action 'self'",
          "frame-ancestors 'none'"
        ],
        "; "
      )

    conn
    |> put_resp_header("content-security-policy", csp)
    |> put_resp_header(
      "permissions-policy",
      "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
    )
    |> put_resp_header("cross-origin-opener-policy", "same-origin")
    |> register_before_send(&secure_cookies/1)
  end

  defp secure_cookies(%Plug.Conn{scheme: :https} = conn) do
    cookies = Map.new(conn.resp_cookies, fn {k, v} -> {k, Map.put(v, :secure, true)} end)

    %{conn | resp_cookies: cookies}
    |> put_resp_header("strict-transport-security", "max-age=31536000; includeSubDomains")
  end

  defp secure_cookies(conn), do: conn
end
