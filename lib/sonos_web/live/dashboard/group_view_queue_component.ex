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
    |> assign(
      queue: nil,
      group: nil,
      number_of_tracks: nil,
      queue_position: nil,
      queue_index: nil
    )
    |> then(fn socket -> {:ok, socket} end)
  end

  def service_updated_event(id, "Queue:1") do
    # this means new songs were added to the queue perhaps, or that we've completely
    # changed the queue.
    send_update(__MODULE__, id: id, queue_updated: true)
  end

  def service_updated_event(id, "AVTransport:1") do
    # this can mean we've changed songs, but also often it just means we've paused or stopped.
    send_update(__MODULE__, id: id, song_changed: true)
  end

  # we don't care about any other events.
  def service_updated_event(_id, _), do: :ok

  @impl true
  def update(%{song_changed: true}, socket) do
    group = socket.assigns.group
    leader = group.members |> hd |> Map.get(:device)

    old_queue_position = socket.assigns.queue_position
    old_number_of_tracks = socket.assigns.number_of_tracks

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

    socket =
      socket
      |> assign(:queue_position, queue_position)
      |> assign(:number_of_tracks, num_tracks)

    {:ok, _socket} =
      if old_queue_position != queue_position || old_number_of_tracks != num_tracks do
        update(%{queue_updated: true}, socket)
      else
        {:ok, socket}
      end
  end

  def update(%{queue_updated: true}, socket) do
    # technically we should be checking the UpdateID of the queue_index we are
    # subscribed to and if it is unchanged, we don't have to do anything at all.
    # but in reality no one is ever going to use a queue_index other than 0.
    # also there's technically no function to get it, but it exists in the server cache
    # so it is technically inspectable.

    queue_position = socket.assigns.queue_position
    num_tracks = socket.assigns.number_of_tracks

    leader = socket.assigns.group.members |> hd |> Map.get(:device)

    queue =
      if queue_position && num_tracks do
        Sonos.Utils.contiguous_ranges_around(queue_position, num_tracks,
          side_count: 3
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
    group = group |> SonosWeb.Dashboard.GroupViewComponent.get_group()

    socket =
      socket
      |> assign(:group, group)
      |> assign(:queue_index, queue_index)

    # not sure I like the finicky reuse of the update function like this, but it
    # does cut down on calls to the device. A song update implies a queue update at
    # this time because we need to know where in the queue your current song is.
    {:ok, _socket} = update(%{song_changed: true}, socket)
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
