defmodule SonosWeb.EpisodeLive.Index do
  use SonosWeb, :live_view

  alias Sonos.Episodes
  alias Sonos.Podcasts

  @impl true
  def mount(%{"id" => podcast_id} = params, _session, socket) do
    podcast = Podcasts.get_podcast!(podcast_id)
    episodes = Episodes.list_episodes(podcast)

    socket
    |> assign(:podcast, podcast)
    |> stream(:episodes, episodes)
    |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Episodes")
  end

  @impl true
  def handle_info({SonosWeb.EpisodeLive.EpisodeEditComponent, {:saved, episode}}, socket) do
    {:noreply, stream_insert(socket, :episodes, episode)}
  end

  @impl true
  def handle_info({SonosWeb.EpisodeLive.EpisodeEditComponent, {:deleted, episode}}, socket) do
    {:noreply, stream_delete(socket, :episodes, episode)}
  end
end
