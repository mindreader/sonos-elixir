defmodule SonosWeb.Dashboard do
  require Logger

  use SonosWeb, :live_view
  alias __MODULE__

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component :if={@action == :list_groups}
      id="group-list"
      module={SonosWeb.Dashboard.GroupListComponent}
    />

    <.live_component :if={@action == :view_group}
      id={"group-view-#{@group_id}"}
      module={SonosWeb.Dashboard.GroupViewComponent}
      group={@group_id}
    />
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    self() |> Process.send_after(:periodic_update, :timer.seconds(20))

    Phoenix.PubSub.subscribe(Sonos.PubSub, "Sonos.Event")

    socket
    |> assign(:action, :list_groups)
    |> assign(:group_id, nil)
    |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def handle_params(%{"group" => group_id}, _url, socket) do
    socket
    |> assign(:action, :view_group)
    |> assign(:group_id, group_id)
    |> then(fn socket -> {:noreply, socket} end)
  end

  def handle_params(_params, _url, socket) do
    socket |> assign(:action, :list_groups) |> then(fn socket -> {:noreply, socket} end)
  end

  # TODO FIXME for as long as this live view is open we need to continually renew subscriptions for the
  # open live component. They cannot be allowed to ever expire.

  @impl true
  def handle_info(event, socket) do
    # any event from Sonos.Server over pubsub or any periodic event, call the primary refresh
    # for the currently loaded component, which will cause subscriptions to the sonos devices
    # that that component relies on to be kept up to date, while all others eventually expire.
    case socket.assigns[:action] do
      :list_groups ->
        send_update(Dashboard.GroupListComponent, id: "group-list")

      :view_group ->
        send_update(Dashboard.GroupViewComponent, id: "group-view-#{socket.assigns.group_id}", group: socket.assigns.group_id)

      _ ->
        :ok
    end

    if event == :periodic_update do
      self() |> Process.send_after(:periodic_update, :timer.seconds(20))
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
