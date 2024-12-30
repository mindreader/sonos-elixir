defmodule SonosWeb.Dashboard do
  require Logger

  use SonosWeb, :live_view
  alias __MODULE__

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component :if={@live_action == :list}
      id="group-list"
      module={SonosWeb.Dashboard.GroupListComponent}
    />

    <.live_component :if={@live_action == :group}
      id={"group-view-#{@group_id}"}
      module={SonosWeb.Dashboard.GroupViewComponent}
      group={@group_id}
    />

    <.live_component :if={@live_action == :queue}
      id={"group-queue-#{@group_id}"}
      module={SonosWeb.Dashboard.GroupViewQueueComponent}
      group={@group_id}
      queue={@queue_id}
    />

    <.live_component :if={@live_action == :playlists}
      id="playlists"
      module={SonosWeb.Dashboard.PlaylistsComponent}
    />
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    # periodic updates are to ensure subscriptions are maintained.
    self() |> Process.send_after(:periodic_update, :timer.seconds(60))

    Phoenix.PubSub.subscribe(Sonos.PubSub, "Sonos.Event")

    socket
    |> assign(:group_id, nil)
    |> assign(:queue_id, nil)
    |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def handle_params(%{"group" => group_id, "queue" => queue_index}, _url, socket) do
    queue_index = queue_index |> String.to_integer()

    socket
    |> assign(:live_action, :queue)
    |> assign(:group_id, group_id)
    |> assign(:queue_id, queue_index)
    |> then(fn socket -> {:noreply, socket} end)
  end

  @impl true
  def handle_params(%{"group" => group_id}, _url, socket) do
    socket
    |> assign(:live_action, :group)
    |> assign(:group_id, group_id)
    |> then(fn socket -> {:noreply, socket} end)
  end

  def handle_params(_params, _url, socket) do
    socket
    |> then(fn socket -> {:noreply, socket} end)
  end

  # TODO these stanzas could just be remote calls into their respective components allowing us to keep the logic inside of the components.
  @impl true
  def handle_info(event, socket) do
    # any event from Sonos.Server over pubsub or any periodic event, call the primary refresh
    # for the currently loaded component, which will cause subscriptions to the sonos devices
    # that that component relies on to be kept up to date, while all others eventually expire.
    case socket.assigns[:live_action] do
      :list ->
        # TODO both of these stanzas only care about certain types of events, put them into their components.
        send_update(Dashboard.GroupListComponent, id: "group-list")

      :group ->
        send_update(Dashboard.GroupViewComponent,
          id: "group-view-#{socket.assigns.group_id}",
          group: socket.assigns.group_id
        )

      :queue ->
        case event do
          # TODO the :periodic update event is needed to maintain a subscription to know when the queue changes, but
          # but refreshing the entire queue actually makes a request every time because it is not cached, so we could
          # just maintain the subscription and not even refresh the live view state in this case.
          # :periodic_update ->
          #  Sonos.Server.cache_service(endpoint, {device.api}.MediaRenderer.Queue
          {:service_updated, _usn, service} ->
            "group-queue-#{socket.assigns.group_id}"
            |> Dashboard.GroupViewQueueComponent.service_updated_event(service)

          _ ->
            :ok
        end

      _ ->
        :ok
    end

    if event == :periodic_update do
      self() |> Process.send_after(:periodic_update, :timer.seconds(60))
    end

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
