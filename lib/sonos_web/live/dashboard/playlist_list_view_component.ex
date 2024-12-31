defmodule SonosWeb.Dashboard.PlaylistListViewComponent do
  use SonosWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
     VIEW PLAYLIST <%= @playlist.name %>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(%{playlist: playlist_id}, socket) do
    playlist = playlist_id |> Sonos.Playlist.get()

    socket
    |> assign(:playlist, playlist)
    |> then(fn socket -> {:ok, socket} end)
  end
end
