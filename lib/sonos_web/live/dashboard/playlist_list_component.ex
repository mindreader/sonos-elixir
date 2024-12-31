defmodule SonosWeb.Dashboard.PlaylistsComponent do
  use SonosWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%= for playlist <- @playlists do %>
        <.player_playlist id={playlist.id} name={playlist.name} target={@myself} />
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, playlists} =
      Sonos.Repo.transaction(fn ->
        Sonos.Playlist.stream()
        |> Enum.to_list()
      end)

    socket
    |> assign(:playlists, playlists)
    |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def update(_assigns, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("view-playlist", %{"playlist_id" => playlist_id}, socket) do
    socket
    |> push_patch(to: ~p"/playlist/#{playlist_id}")
    |> then(fn socket -> {:noreply, socket} end)
  end
end
