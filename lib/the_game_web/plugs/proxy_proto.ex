defmodule TheGameWeb.Plugs.ProxyProto do
  @moduledoc "Honour `X-Forwarded-Proto` only when explicitly running behind a trusted proxy."
  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:the_game, :trust_proxy, false) do
      Plug.RewriteOn.call(conn, Plug.RewriteOn.init([:x_forwarded_proto]))
    else
      conn
    end
  end
end
