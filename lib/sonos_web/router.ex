defmodule SonosWeb.Router do
  use SonosWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {SonosWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", SonosWeb do
    pipe_through(:browser)

    live("/", Dashboard, :list)
    # TODO remove references in code
    live("/groups", Dashboard, :list)

    scope "/group" do
      live("/", Dashboard, :list)
      live("/:group", Dashboard, :group)
      live("/:group/queue/:queue", Dashboard, :queue)
    end

    scope "/playlist" do
      live("/", Dashboard, :playlists)
      live("/:playlist", Dashboard, :playlist)
    end
  end

  # Other scopes may use custom stacks.
  scope "/event/:usn/:service", SonosWeb do
    pipe_through(:api)

    match(:notify, "/", Events, :webhook)
  end

  scope "/audio", SonosWeb do
    pipe_through(:api)

    get("/:filename", Audio, :fetch)
  end

  # Enable LiveDashboaod and Swoosh mailbox preview in development
  if Application.compile_env(:sonos_elixir, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: SonosWeb.Telemetry)
      #  forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
