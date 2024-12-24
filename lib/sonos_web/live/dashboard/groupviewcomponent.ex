defmodule SonosWeb.Dashboard.GroupViewComponent do
  use SonosWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"group-view-#{@group.id}"}>
      <.player_group
        id={@group.id}
        target={@myself}
        name={@group.name}
        playing={@group.playing}
        shuffle={@group.shuffle}
        continue={@group.continue}
        volume={@group.volume}
      />
    </div>
    """
  end

  def get_group(id) do
    Sonos.group(id)
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

      %{
        id: group.id,
        name: name,
        members: group.members,
        playing: playing,
        shuffle: Sonos.shuffle_enabled?(play_state),
        continue: Sonos.continue_enabled?(play_state),
        volume: volume
      }
    end)
  end

  @impl true
  def mount(socket) do
    socket |> assign(:group, nil) |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def update(assigns, socket) do
    assigns.group
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

    socket.assigns.group
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
end
