defmodule SonosWeb.Dashboard.PlaylistsComponent do
  use SonosWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      LIST OF PLAYLISTS
      <%= for playlist <- @playlists do %>
        <%= playlist.name %>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, playlists} = Sonos.Repo.transaction(fn ->
      Sonos.Playlist.stream_playlists()
      |> Enum.to_list()
    end)

    socket
    |> assign(:playlists, playlists)
    |> then(fn socket -> {:ok, socket} end)
  end
end
