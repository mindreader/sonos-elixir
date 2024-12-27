defmodule SonosWeb.Dashboard.GroupViewQueueComponent do
  use SonosWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""

    <div id="group-view-queue">
      <.player_queue queue={@queue} target={@myself}/>
    </div>

    """
 end

  @impl true
  def mount(socket) do
    socket
    |> assign(:queue, nil)
    |> assign(:group, nil)
    |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def update(%{queue: queue, group: group}, socket) do
    # The double render is kind of an issue here because this is an interactive component, and having
    # a rendered component that is not interactive is at best confusing.

    group = group |> SonosWeb.Dashboard.GroupViewComponent.get_group()
    leader = group.members |> hd |> Map.get(:device)

    num_tracks = leader |> Sonos.get_media_info()
    |> then(fn
      {:ok, %Sonos.Api.Response{outputs: outputs}} -> case outputs[:nr_tracks] do
        nil -> nil
        nr_tracks -> nr_tracks
      end
      _ -> nil
    end)

    queue_position = leader |> Sonos.get_position_info()
      |> then(fn
        {:ok, %Sonos.Api.Response{outputs: outputs}} -> outputs[:track]
        _ -> nil
      end)
      |> then(fn
        nil -> nil
        track -> track - 1
      end)

    preferred_positions_on_either_side = 3

    queue =
    if queue_position && num_tracks do
      Sonos.Utils.contiguous_ranges_around(queue_position, num_tracks, side_count: preferred_positions_on_either_side)
    else
      []
    end
    |> Enum.map(fn {offset, count} ->
      leader
      |> Sonos.stream_queue(0, offset: offset, per_call: count)
      |> Stream.map(fn entry ->
        entry = entry
        |> Map.put(:current, entry.index == queue_position)
        |> Map.put(:index, "#{entry.index + 1}")
        {entry.id, entry}
      end)
      |> Stream.take(count)
    end)
    |> Stream.concat()

    socket
    |> assign(:queue, queue)
    |> assign(:group, group)
    |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def handle_event("view-song", %{"queue_id" => queue_item_id}, socket) do
    _queue = socket.assigns.queue |> Map.get(queue_item_id)

    {:noreply, socket}
  end

  # @impl true
  # def handle_event("move_up", %{"index" => index}, socket) do
  #   # TODO: Implement move up functionality
  #   {:noreply, socket}
  # end

  # @impl true
  # def handle_event("move_down", %{"index" => index}, socket) do
  #   # TODO: Implement move down functionality
  #   {:noreply, socket}
  # end

  # @impl true
  # def handle_event("remove", %{"index" => index}, socket) do
  #   # TODO: Implement remove functionality
  #   {:noreply, socket}
  # end
end
