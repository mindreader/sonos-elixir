defmodule SonosWeb.Dashboard.GroupViewComponent do
  use SonosWeb, :live_component

  # TODO we need a better looking player group for dedicated group use that spans entire screen
  # etc.
  @impl true
  def render(assigns) do
    ~H"""
    <div id="group-view">
      <div
        class="bg-slate-500 text-white m-2 p-2 rounded-lg border border-slate-600"
        phx-click="view-queue"
        phx-target={@myself}
      >
        View Queue
      </div>

      <.track_info
        target={@myself}
        artist={@group.artist}
        album={@group.album}
        song={@group.song}
        track_duration={@group.track_duration}
        art={@group.art}
      />

      <.player_group
        id={@group.id}
        target={@myself}
        name={@group.name}
        playing={@group.playing}
        shuffle={Sonos.shuffle_enabled?(@group.play_state)}
        continue={Sonos.continue_enabled?(@group.play_state)}
        volume={@group.volume}
      />
    </div>
    """
  end

  @doc """
   This event main mean the device has moved to another song in the same queue, which we need to keep track of
  """
  def service_updated_event(group_id, "AVTransport:1") do
    # TODO if we had a way of knowing which group this usn was in, we could avoid even sending other devices
    # changes and avoid a few more calls.
    send_update(Dashboard.GroupViewQueueComponent,
      id: "group-queue-#{group_id}",
      group: group_id,
      queue: 0
    )
  end

  def get_group(id) do
    id
    |> Sonos.group()
    |> then(fn group ->
      member_count = group.members |> Enum.count()
      leader = group.members |> hd |> Map.get(:device)

      volume =
        leader
        |> Sonos.get_group_volume()
        |> then(fn {:ok, %Sonos.Api.Response{} = resp} -> resp.outputs[:current_volume] end)

      playing = leader |> Sonos.is_playing?()
      play_state = leader |> Sonos.get_play_state()

      name = leader.room_name

      name =
        if member_count > 1 do
          "#{name} + #{member_count - 1}"
        else
          name
        end

      audio_info =
        leader
        |> Sonos.get_audio_info()
        |> then(fn {:ok, %Sonos.Api.Response{} = resp} -> resp.outputs end)

      track_duration = audio_info[:track_duration]
      track_meta_data = audio_info[:track_meta_data]
      song = track_meta_data.song
      artist = track_meta_data.artist
      album = track_meta_data.album
      art = leader.endpoint <> track_meta_data.art

      queue = [
        %{
          song: "Songname",
          artist: "Artistname",
          album: "Albumname",
          art: "https://picsum.photos/200/300"
        }
      ]

      %{
        id: group.id,
        name: name,
        members: group.members,
        playing: playing,
        play_state: play_state,
        volume: volume,
        artist: artist,
        album: album,
        song: song,
        track_duration: track_duration,
        art: art,
        queue: queue
      }
    end)
  end

  @impl true
  def mount(socket) do
    socket |> assign(:group, nil) |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def update(%{group: group_id}, socket) do
    group_id
    |> get_group()
    |> then(fn group ->
      socket |> assign(:group, group) |> then(fn socket -> {:ok, socket} end)
    end)
  end

  # any other event, update existing group.
  @impl true
  def update(_, socket) do
    socket.assigns.group.id
    |> get_group()
    |> then(fn group ->
      socket |> assign(:group, group) |> then(fn socket -> {:ok, socket} end)
    end)
  end

  @impl true
  def handle_event("play", _params, socket) do
    socket.assigns.group.members
    |> hd
    |> Map.get(:device)
    |> Sonos.play()

    {:noreply, socket}
  end

  @impl true
  def handle_event("pause", _params, socket) do
    socket.assigns.group.members
    |> hd
    |> Map.get(:device)
    |> Sonos.pause()

    {:noreply, socket}
  end

  @impl true
  def handle_event("next", _params, socket) do
    socket.assigns.group.members
    |> hd
    |> Map.get(:device)
    |> Sonos.next()

    {:noreply, socket}
  end

  @impl true
  def handle_event("previous", _params, socket) do
    socket.assigns.group.members
    |> hd
    |> Map.get(:device)
    |> Sonos.previous()

    {:noreply, socket}
  end

  @impl true
  def handle_event("continue", _params, socket) do
    play_state = socket.assigns.group.play_state

    new_play_state =
      case play_state do
        :shuffle_norepeat -> :shuffle_repeat_one
        :shuffle_repeat_one -> :shuffle
        :shuffle -> :shuffle_norepeat
        :normal -> :repeat_one
        :repeat_one -> :repeat_all
        :repeat_all -> :normal
      end

    socket.assigns.group.members
    |> hd
    |> Map.get(:device)
    |> Sonos.set_play_state(new_play_state)

    {:noreply, socket}
  end

  @impl true
  def handle_event("shuffle", _params, socket) do
    play_state = socket.assigns.group.play_state

    new_play_state =
      case play_state do
        :shuffle_norepeat -> :normal
        :shuffle_repeat_one -> :repeat_one
        :shuffle -> :repeat_all
        :normal -> :shuffle_norepeat
        :repeat_one -> :shuffle_repeat_one
        :repeat_all -> :shuffle
      end

    socket.assigns.group.members
    |> hd
    |> Map.get(:device)
    |> Sonos.set_play_state(new_play_state)

    {:noreply, socket}
  end

  @impl true
  def handle_event("volume", %{"volume" => volume}, socket) do
    volume
    |> Integer.parse()
    |> then(fn
      {i, _} when i >= 0 and i <= 100 -> i
      _ -> socket.assigns.group.volume
    end)
    |> then(fn volume ->
      socket.assigns.group.members
      |> hd
      |> Map.get(:device)
      |> Sonos.set_group_volume(volume)
      |> then(fn _ -> {:noreply, socket} end)
    end)
  end

  @impl true
  def handle_event("view-queue", _params, socket) do
    socket
    |> push_patch(to: ~p"/group/#{socket.assigns.group.id}/queue/0")
    |> then(fn socket -> {:noreply, socket} end)
  end

  def handle_event("view-group", _params, socket) do
    IO.puts("TODO REMOVE THIS EVENT")
    # TODO when we have a more specific group view defined, we can remove this as there
    # will no longer be a top level phx-click back to this page to ignore.

    {:noreply, socket}
  end
end
