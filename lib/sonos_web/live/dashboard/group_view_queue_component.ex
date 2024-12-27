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
    |> assign(queue: nil, group: nil, number_of_tracks: nil, queue_position: nil, queue_index: nil)
    |> then(fn socket -> {:ok, socket} end)
  end

  def service_updated_event(id, group_id, "Queue:1") do
    # this means new songs were added to the queue perhaps, or that we've completely
    # changed the queue.
    send_update(Dashboard.GroupViewQueueComponent,
      id: "group-queue-#{group_id}",
      queue_updated: true
    )
  end

  def service_updated_event(id, "AVTransport:1") do
    # this can mean we've changed songs, but also often it just means we've paused or stopped.
    send_update(__MODULE__, id: id, song_changed: true)
  end

  # we don't care about any other events.
  def service_updated_event(id, _), do: :ok

  @impl true
  def update(%{song_changed: true}, socket) do
    group = socket.assigns.group
    leader = group.members |> hd |> Map.get(:device)

    num_tracks =
      leader
      |> Sonos.get_media_info()
      |> then(fn
        {:ok, %Sonos.Api.Response{outputs: outputs}} ->
          case outputs[:nr_tracks] do
            nil -> nil
            nr_tracks -> nr_tracks
          end

        _ ->
          nil
      end)

    queue_position =
      leader
      |> Sonos.get_position_info()
      |> then(fn
        {:ok, %Sonos.Api.Response{outputs: outputs}} -> outputs[:track]
        _ -> nil
      end)
      |> then(fn
        nil -> nil
        track -> track - 1
      end)

    socket
    |> assign(
      number_of_tracks: num_tracks,
      queue_position: queue_position
    )
    |> then(fn socket -> {:ok, socket} end)
  end

  def update(%{queue_updated: true}, socket) do
    queue_position = socket.assigns.queue_position
    num_tracks = socket.assigns.number_of_tracks

    preferred_positions_on_either_side = 3

    leader = socket.assigns.group.members |> hd |> Map.get(:device)

    queue =
      if queue_position && num_tracks do
        Sonos.Utils.contiguous_ranges_around(queue_position, num_tracks,
          side_count: preferred_positions_on_either_side
        )
      else
        []
      end
      |> Enum.map(fn {offset, count} ->
        leader
        |> Sonos.stream_queue(socket.assigns.queue_index, offset: offset, per_call: count)
        |> Stream.map(fn entry ->
          entry =
            entry
            |> Map.put(:current, entry.index == queue_position)
            |> Map.put(:index, "#{entry.index + 1}")

          {entry.id, entry}
        end)
        |> Stream.take(count)
      end)
      |> Enum.concat()

    socket
    |> assign(:queue, queue)
    |> then(fn socket -> {:ok, socket} end)
  end

  def update(%{queue: queue_index, group: group}, socket) do
    # The double render is kind of an issue here because this is an interactive component, and having
    # a rendered component that is not interactive is at best confusing.
    group = group |> SonosWeb.Dashboard.GroupViewComponent.get_group()

    socket =
      socket
      |> assign(:group, group)
      |> assign(:queue_index, queue_index)

    {:ok, socket} = update(%{song_changed: true}, socket)
    {:ok, socket} = update(%{queue_updated: true}, socket)
  end

  @impl true
  def handle_event("view-song", %{"queue_id" => queue_item_id}, socket) do
    _queue = socket.assigns.queue |> Enum.find(fn {id, _} -> id == queue_item_id end)

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
