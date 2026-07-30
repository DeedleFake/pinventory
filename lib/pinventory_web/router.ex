defmodule PinventoryWeb.Router do
  use PinventoryWeb, :router

  import PinventoryWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PinventoryWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PinventoryWeb do
    pipe_through :browser

    live_session :items do
      live "/", ItemsLive, :index

      live "/item", EditItemLive, :new
      live "/item/:item_id", EditItemLive, :edit

      live "/locations", LocationsLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", PinventoryWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:pinventory, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PinventoryWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", PinventoryWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{PinventoryWeb.UserAuth, :require_authenticated}] do
      live "/user/settings", UserLive.Settings, :edit
      live "/user/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/user/update-password", UserSessionController, :update_password
  end

  scope "/", PinventoryWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{PinventoryWeb.UserAuth, :mount_current_scope}] do
      live "/user/register", UserLive.Registration, :new
      live "/user/log-in", UserLive.Login, :new
      live "/user/log-in/:token", UserLive.Confirmation, :new
    end

    post "/user/log-in", UserSessionController, :create
    delete "/user/log-out", UserSessionController, :delete
  end
end
