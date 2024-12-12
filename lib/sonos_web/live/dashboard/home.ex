defmodule SonosWeb.Dashboard do
  use SonosWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    #    podcast = Podcasts.get_podcast!(podcast_id)
    #    episodes = Episodes.list_episodes(podcast)

    podcast = %{
      title: "Podcast 1",
      created_at: DateTime.utc_now(),
      published_at: DateTime.utc_now()
    }

    IO.inspect(podcast, label: "podcast")

    socket
    |> assign(:podcast, podcast)
    |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, socket}
  end

  #  defp apply_action(socket, :index, _params) do
  #    socket
  #    |> assign(:page_title, "Listing Episodes")
  #  end

  #  @impl true
  #  def handle_info({SonosWeb.EpisodeLive.EpisodeEditComponent, {:saved, episode}}, socket) do
  #    {:noreply, socket}
  #  end
  #
  #  @impl true
  #  def handle_info({SonosWeb.EpisodeLive.EpisodeEditComponent, {:deleted, episode}}, socket) do
  #    {:noreply, stream_delete(socket, :episodes, episode)}
  #  end
end
