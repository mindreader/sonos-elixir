defmodule SonosWeb.Dashboard.GroupViewQueueComponent do
  use SonosWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div id="group-view-queue">
        <.player_queue
          queue={@queue}
          target={@myself}
          show_modal={@show_modal}
        />

      </div>

      <.song_operations_modal
        id="view-song-modal"
        target={@myself}
        song={@viewing_song && @viewing_song.track.title}
        artist={@viewing_song && @viewing_song.track.creator}
      />
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
      queue_index: nil,
      show_modal: false,
      viewing_song: nil
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
      |> assign(:viewing_song, nil)

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

    # TODO remove this contiguous ranges stuff, the sonos queue doesn't even cycle the way
    # I thought it did, so we might as well just cap the start and end indexes instead of
    # doing this wraparound stuff. It might still be worth doing if we are in
    # continue / repeat mode, though...
    queue =
      if queue_position && num_tracks do
        Sonos.Utils.contiguous_ranges_around(queue_position, num_tracks, side_count: 3)
      else
        []
      end
      |> Enum.map(fn {offset, count} ->
        leader
        |> Sonos.stream_queue(socket.assigns.queue_index, offset: offset, per_call: count)
        |> Stream.map(fn %{index: index, track: %Sonos.Track{}} = entry ->
          entry =
            entry
            |> Map.put(:current, index == queue_position)
            |> Map.put(:index, index)

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
  def handle_event("view-song", %{"track_id" => track_id}, socket) do
    socket.assigns.queue
    |> Enum.find(fn {id, _} -> id == track_id end)
    |> then(fn
      nil ->
        socket

      {_, song} ->
        socket
        |> push_event("show-modal", %{id: "view-song-modal"})
        |> assign(:viewing_song, song)
    end)
    |> then(fn socket -> {:noreply, socket} end)
  end

  def handle_event("play-now", _, socket) do
    IO.puts("play-now #{socket.assigns.viewing_song.track.title}")
    track_id = socket.assigns.viewing_song.index

    leader = socket.assigns.group.members |> hd |> Map.get(:device)

    leader
    |> Sonos.seek_queue_position(track_id)

    {:noreply, socket}
  end

  # This is done in the app by adding the song you want to the queue, then seeking to it.
  # if it is already in the queue it will just have the song in the queue twice
  # Not really sure that this belongs here, it might be better a part of a music service
  def handle_event("play-next", _, socket) do
    IO.puts("play-next #{socket.assigns.viewing_song.track.title}")
    index = socket.assigns.viewing_song.index

    leader = socket.assigns.group.members |> hd |> Map.get(:device)

    track =
      leader
      |> Sonos.stream_queue(0, per_call: 15)
      |> Stream.filter(fn entry ->
        entry.index == index
      end)
      |> Enum.take(1)
      |> List.first()

    # TODO FIXME this plays it immediately, we want to play it next, so probably the right
    # way is to remove it from the queue and then add it just after the current song.
    track |> Sonos.seek_queue_position(track.index)

    {:noreply, socket}
  end

  def handle_event("add-to-playlist", _, socket) do
    IO.puts("add-to-playlist #{socket.assigns.viewing_song.track.title}")
    {:noreply, socket}
  end

  def handle_event("remove-from-queue", _, socket) do
    track_id = socket.assigns.viewing_song.index
    leader = socket.assigns.group.members |> hd |> Map.get(:device)

    leader |> Sonos.remove_from_queue(track_id)

    socket
    |> then(fn socket -> {:noreply, socket} end)
  end

  # TODO FIXME all of these need to close the modal when they are done.
end
