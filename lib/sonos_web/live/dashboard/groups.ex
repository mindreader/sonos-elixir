defmodule SonosWeb.Dashboard.GroupListComponent do
  require Logger

  use SonosWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id="group-list">
     <div :for={group <- @groups |> Map.values()}>
       <.player_group
         id={group.id}
         name={group.name}
         target={@myself}
         playing={group.playing}
         shuffle={group.shuffle}
         continue={group.continue}
       />
     </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    groups =
      Sonos.groups()
      |> Enum.map(fn group ->
        member_count = group.members |> Enum.count()

        name = group.members |> hd |> Map.get(:device) |> Map.get(:room_name)

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
           shuffle: false,
           playing: false,
           continue: false
         }}
      end)
      |> Map.new()

    socket
    |> assign(:groups, groups)
    |> then(fn socket -> {:ok, socket} end)
  end

  @impl true
  def update(_assigns, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("play", %{"value" => group_id}, socket) do
      socket.assigns.groups
      |> IO.inspect(label: "groups")
      |> Map.get(group_id)
      |> Map.get(:members)
      # the first member is the leader
      |> hd
      |> Map.get(:device)
      |> Sonos.play()
      |> then(fn
        {:ok, _} ->
          socket =
            socket
            |> assign(
              :groups,
              socket.assigns.groups
              |> put_in([group_id, :playing], true)
            )

          {:noreply, socket}

        {:error, _} ->
          Logger.error("Failed to play group #{group_id}")

          {:noreply, socket}
      end)
  end

  @impl true
  def handle_event("pause", %{"value" => group_id}, socket) do
      socket.assigns.groups
      |> Map.get(group_id)
      |> Map.get(:members)
      # the first member is the leader
      |> hd
      |> Map.get(:device)
      |> Sonos.pause()

    socket =
      socket
      |> assign(
        :groups,
        socket.assigns.groups
        |> put_in([group_id, :playing], false)
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("shuffle", %{"value" => group_id}, socket) do
    shuffle =
      socket.assigns.groups
      |> IO.inspect(label: "groups")
      |> Map.get(group_id)
      |> Map.get(:shuffle)

    socket =
      socket
      |> assign(
        :groups,
        socket.assigns.groups
        |> put_in([group_id, :shuffle], not shuffle)
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("next", %{"value" => group_id}, socket) do
    IO.puts("next! #{group_id}")

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
  def handle_event("previous", %{"value" => group_id}, socket) do
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
  def handle_event("continue", %{"value" => group_id}, socket) do
    continue =
      socket.assigns.groups
      |> Map.get(group_id)
      |> Map.get(:continue)

    socket =
      socket
      |> assign(
        :groups,
        socket.assigns.groups
        |> put_in([group_id, :continue], not continue)
      )

    {:noreply, socket}
  end
end
