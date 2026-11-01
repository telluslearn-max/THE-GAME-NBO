defmodule TheGameWeb.Router do
  use TheGameWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {TheGameWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TheGameWeb do
    pipe_through :browser

    get "/", MenuController, :index
    get "/cart", CartController, :show
    post "/orders", CartController, :create
    get "/order/:id", OrderController, :show
    get "/orders", StubController, :orders
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
end
