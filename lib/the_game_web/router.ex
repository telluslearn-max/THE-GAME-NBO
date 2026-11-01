defmodule TheGameWeb.Router do
  use TheGameWeb, :router
  import TheGameWeb.StaffAuth, only: [require_staff: 2]

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

  pipeline :noindex do
    plug :put_noindex
  end

  pipeline :admin_css do
    plug :put_admin_css
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TheGameWeb do
    pipe_through :browser

    get "/", MenuController, :index
    get "/offline", OfflineController, :show
    get "/cart", CartController, :show
    post "/orders", CartController, :create
    get "/orders", OrdersController, :index
  end

  scope "/", TheGameWeb do
    pipe_through [:browser, :live_assets]

    live "/order/:id", OrderLive
  end

  scope "/staff", TheGameWeb do
    pipe_through [:browser, :noindex]

    get "/login", StaffSessionController, :new
    post "/login", StaffSessionController, :create
  end

  scope "/staff", TheGameWeb do
    pipe_through [:browser, :noindex, :live_assets, :require_staff]

    post "/logout", StaffSessionController, :delete

    # Everyone signed in sees the board (waiters: only the board).
    live_session :staff_board, on_mount: {TheGameWeb.StaffAuth, :ensure_staff} do
      live "/", Staff.BoardLive
    end

    # Floor staff and managers.
    live_session :staff_floor,
      on_mount: [{TheGameWeb.StaffAuth, :ensure_staff}, {TheGameWeb.StaffAuth, {:area, :floor}}] do
      live "/reviews", Staff.ReviewsLive
      live "/menu", Staff.MenuLive
      live "/today", Staff.TodayLive
    end
  end

  # Manager-only pages, with their own stylesheet.
  scope "/staff", TheGameWeb do
    pipe_through [:browser, :noindex, :live_assets, :require_staff, :admin_css]

    live_session :staff_admin,
      on_mount: [{TheGameWeb.StaffAuth, :ensure_staff}, {TheGameWeb.StaffAuth, {:area, :admin}}] do
      live "/insights", Staff.InsightsLive
      live "/team", Staff.TeamLive
    end
  end

  scope "/", TheGameWeb do
    get "/healthz", HealthController, :show
  end

  scope "/", TheGameWeb do
    pipe_through :api
    get "/menu.json", MenuController, :feed
    get "/cart/check", CartController, :check
    post "/mpesa/callback/:token", MpesaController, :callback
  end

  # Other scopes may use custom stacks.
  # scope "/api", TheGameWeb do
  #   pipe_through :api
  # end

  defp put_live_js(conn, _), do: Plug.Conn.assign(conn, :page_js, "live")
  defp put_admin_css(conn, _), do: Plug.Conn.assign(conn, :admin_css, true)

  # Everything under /staff is private: unindexed, and gets the staff-only stylesheet.
  defp put_noindex(conn, _),
    do: conn |> Plug.Conn.assign(:noindex, true) |> Plug.Conn.assign(:staff_css, true)
end
