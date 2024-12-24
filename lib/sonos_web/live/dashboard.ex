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
      id="group-view"
      module={SonosWeb.Dashboard.GroupViewComponent}
      group={@group}
    />
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(:action, :list_groups)
    |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def handle_params(%{"group" => group}, _url, socket) do
    socket
    |> assign(:action, :view_group)
    |> assign(:group, group)
    |> then(fn socket -> {:noreply, socket} end)
  end

  def handle_params(_params, _url, socket) do
    socket |> assign(:action, :list_groups) |> then(fn socket -> {:noreply, socket} end)
  end

  # TODO FIXME for as long as this live view is open we need to continually renew subscriptions for the
  # open live component. They cannot be allowed to ever expire.

  @impl true
  def handle_info({:updated, service}, socket) do
    case socket.assigns[:action] do
      :list_groups ->
        send_update(Dashboard.GroupListComponent, id: "group-list", service: service)

      :view_group ->
        send_update(Dashboard.GroupViewComponent,
          id: "group-view-#{socket.assigns.group}",
          service: service
        )

      _ ->
        :ok
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
