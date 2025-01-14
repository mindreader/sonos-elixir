defmodule SonosWeb.Dashboard.GroupListComponent do
  require Logger

  use SonosWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id="group-list" class="changeable-volume">
     <div :for={group <- @groups |> Map.values()}>
       <.player_group
         id={group.id}
         target={@myself}
         name={group.name}
         playing={group.playing}
         shuffle={group.shuffle}
         continue={group.continue}
         volume={group.volume}
       />
     </div>
    </div>
    """
  end

  def get_groups() do
    Sonos.groups()
    |> Enum.map(fn group ->
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

      {group.id,
       %{
         id: group.id,
         name: name,
         members: group.members,
         playing: playing,
         volume: volume,
         play_state: play_state,
         shuffle: Sonos.shuffle_enabled?(play_state),
         continue: Sonos.continue_enabled?(play_state)
       }}
    end)
    |> Map.new()
  end

  @impl true
  def mount(socket) do
    socket
    |> assign(:groups, nil)
    |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def update(_assigns, socket) do
    groups = get_groups()

    socket
    |> assign(:groups, groups)
    |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def handle_event("play", %{"group" => group_id}, socket) do
    socket.assigns.groups
    |> Map.get(group_id)
    |> Map.get(:members)
    # the first member is the leader
    |> hd
    |> Map.get(:device)
    |> Sonos.play()
    |> then(fn
      {:ok, _} ->
        {:noreply, socket}

      {:error, _} ->
        Logger.error("Failed to play group #{group_id}")

        {:noreply, socket}
    end)
  end

  @impl true
  def handle_event("pause", %{"group" => group_id}, socket) do
    socket.assigns.groups
    |> Map.get(group_id)
    |> Map.get(:members)
    # the first member is the leader
    |> hd
    |> Map.get(:device)
    |> Sonos.pause()

    {:noreply, socket}
  end

  @impl true
  def handle_event("shuffle", %{"group" => group_id}, socket) do
    play_state =
      socket.assigns.groups
      |> Map.get(group_id)
      |> Map.get(:play_state)

    new_play_state =
      case play_state do
        :shuffle_norepeat -> :normal
        :shuffle_repeat_one -> :repeat_one
        :shuffle -> :repeat_all
        :normal -> :shuffle_norepeat
        :repeat_one -> :shuffle_repeat_one
        :repeat_all -> :shuffle
      end

    socket.assigns.groups
    |> Map.get(group_id)
    |> Map.get(:members)
    |> hd
    |> Map.get(:device)
    |> then(fn device ->
      device |> Sonos.set_play_state(new_play_state)
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("next", %{"group" => group_id}, socket) do
    socket.assigns.groups
    |> Map.get(group_id)
    |> Map.get(:members)
    # the first member is the leader
    |> hd
    |> Map.get(:device)
    |> Sonos.next()

    {:noreply, socket}
  end

  @impl true
  def handle_event("previous", %{"group" => group_id}, socket) do
    socket.assigns.groups
    |> Map.get(group_id)
    |> Map.get(:members)
    # the first member is the leader
    |> hd
    |> Map.get(:device)
    |> Sonos.previous()

    {:noreply, socket}
  end

  @impl true
  def handle_event("continue", %{"group" => group_id}, socket) do
    play_state =
      socket.assigns.groups
      |> Map.get(group_id)
      |> Map.get(:play_state)

    new_state =
      case play_state do
        :shuffle_norepeat -> :shuffle_repeat_one
        :shuffle_repeat_one -> :shuffle
        :shuffle -> :shuffle_norepeat
        :normal -> :repeat_one
        :repeat_one -> :repeat_all
        :repeat_all -> :normal
      end

    socket.assigns.groups
    |> Map.get(group_id)
    |> Map.get(:members)
    |> hd
    |> Map.get(:device)
    |> then(fn device ->
      device |> Sonos.set_play_state(new_state)
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("view-group", %{"group" => group_id}, socket) do
    socket
    |> push_patch(to: ~p"/group/#{group_id}")
    |> then(fn socket -> {:noreply, socket} end)
  end

  def handle_event("volume", %{"volume" => volume, "group" => group_id}, socket) do
    old_volume = socket.assigns.groups |> Map.get(group_id) |> Map.get(:volume)

    volume =
      volume
      |> Integer.parse()
      |> then(fn
        {i, _} when i >= 0 and i <= 100 -> i
        _ -> old_volume
      end)

    socket.assigns.groups
    |> Map.get(group_id)
    |> Map.get(:members)
    |> hd
    |> Map.get(:device)
    |> Sonos.set_group_volume(volume)

    {:noreply, socket}
  end

  @impl true
  def handle_event(ev, payload, socket) do
    Logger.warning("Unhandled event #{ev} with payload #{inspect(payload)}")
    {:noreply, socket}
  end

  def handle_info(:updated, _params, socket) do
    {:noreply, socket}
  end
end
