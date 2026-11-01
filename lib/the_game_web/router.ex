defmodule TheGameWeb.Router do
  use TheGameWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {TheGameWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Pages that use LiveView load the LiveView client; no other page pays for it.
  pipeline :live_assets do
    plug :put_live_js
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TheGameWeb do
    pipe_through :browser

    get "/", MenuController, :index
    get "/cart", CartController, :show
    post "/orders", CartController, :create
    get "/orders", OrdersController, :index
  end

  scope "/", TheGameWeb do
    pipe_through [:browser, :live_assets]

    live "/order/:id", OrderLive
  end

  scope "/", TheGameWeb do
    pipe_through :api
    get "/menu.json", MenuController, :feed
    post "/mpesa/callback/:token", MpesaController, :callback
  end

  # Other scopes may use custom stacks.
  # scope "/api", TheGameWeb do
  #   pipe_through :api
  # end

  defp put_live_js(conn, _), do: Plug.Conn.assign(conn, :page_js, "live")
end
