defmodule SonosWeb.PlayerComponents do
  @moduledoc """
  Reusable components for the player itself.
  """

  import SonosWeb.CoreComponents

  use Phoenix.Component

  alias Phoenix.LiveView.JS
  use Gettext, backend: SonosWeb.Gettext

  attr(:id, :string, required: true)
  attr(:target, :any, required: true)
  attr(:name, :string, required: true)

  def player_playlist(assigns) do
    ~H"""
    <div
      class="bg-slate-500 text-white p-2 rounded-lg border border-slate-600"
      phx-click="view-playlist"
      phx-target={@target}
      phx-value-playlist_id={@id}
    >
      <%= @name %>
    </div>
    """
  end

  attr(:target, :any, required: true)
  attr(:queue, :list, required: true)
  attr(:show_modal, :boolean, default: false)

  def player_queue(assigns) do
    ~H"""
     <.table
         id="queue"
         rows={@queue}
         row_id={&elem(&1, 0)}
         row_item={&elem(&1, 1)}
         row_click={fn {id, _} ->
           JS.push("view-song", target: @target, value: %{track_id: id})
         end}
         row_highlight={fn {_, entry} -> entry.current end}
     >
       <:col :let={entry} label="Index"><%= entry.index + 1 %></:col>
       <:col :let={entry} label="Song"><%= entry.track.title %></:col>
       <:col :let={entry} label="Artist"><%= entry.track.creator %></:col>
       <:col :let={entry} label="Album"><%= entry.track.album %></:col>
       <:col :let={entry} label="Duration"><%= entry.track.content.duration %></:col>
     </.table>
    """
  end

  # TODO this doesn't technically need to be identified by group, because there will only ever be
  # one on screen, that said, it could be made to work that way if ever needed.
  attr(:target, :any, required: true)
  attr(:song, :string)
  attr(:artist, :string)
  attr(:album, :string)
  attr(:track_duration, :string)
  attr(:art, :string)

  # TODO FIXME if the song name is too long it will overflow the container. truncate doesn't
  # seem to work...
  def track_info(assigns) do
    ~H"""
    <div class="bg-slate-500 text-white rounded-lg p-2 px-4 border border-slate-600">
      <img src={@art} class="m-2 mx-auto mb-0"/>
      <div class="grid auto-cols-min gap-x-2 text-nowrap tracking-tight">
          <.icon name="hero-musical-note" class="size-4 row-start-1"/>
          <div class="text-sm col-start-2">
            <%= @song %> - <%= @album %>
          </div>
          <.icon name="hero-at-symbol" class="size-4 row-start-2 col-start-1"/>
          <div class="text-sm">
            <%= @artist %>
          </div>
          <div class="text-xs row-start-3 col-start-2">
            <%= @track_duration %>
          </div>
     </div>
    </div>
    """
  end

  def song_navigation(assigns) do
    ~H"""
    <div class="flex flex-row p-2">
      <div
        class="text-white p-1 text-xs rounded-lg mx-1 border-2 border-slate-500"
        phx-click="view-queue"
        phx-target={@target}
      >
        View Queue
      </div>
        <div
          class="text-white p-1 text-xs rounded-lg mx-1 border-2 border-slate-500"
          phx-click="view-playlists"
          phx-target={@target}
        >
          Recently Played
        </div>


    </div>
    """
  end

  def dedicated_player_group(assigns) do
    ~H"""
    <div
      class="bg-slate-500 text-white p-2 rounded-lg border border-slate-600"
    >


      <div>
        <div class="flex flex-nowrap justify-center gap-2 mx-2 leading-none">

          <div
            phx-click="shuffle"
            phx-target={@target}
            phx-value-group={@id}
            class={["my-auto", @shuffle && "text-slate-500 bg-white rounded-full border-2 border-slate-400 shadow-sm"]}
          >
            <.icon name="icon-shuffle" class="size-6"/>
          </div>

          <div
            phx-click="previous"
            phx-target={@target}
            phx-value-group={@id}
            class="my-auto"
          >
            <.icon name="hero-backward" class="size-14"/>
          </div>

          <div :if={!@playing} phx-click="play" phx-target={@target} phx-value-group={@id}>
            <.icon name="hero-play-solid" class="size-20" />
          </div>

          <div :if={@playing} phx-click="pause" phx-target={@target} phx-value-group={@id}>
            <.icon name="hero-pause-solid" class="size-20" />
          </div>

          <div
            phx-click="next"
            phx-target={@target}
            phx-value-group={@id}
            class="my-auto"
          >
            <.icon name="hero-forward" class="size-14"/>
          </div>

          <div
            phx-click="continue"
            phx-target={@target}
            phx-value-group={@id}
            class={["my-auto", @continue && "text-slate-500 bg-white rounded-full border-2 border-slate-400 shadow-sm"]}
          >
            <.icon name="hero-arrow-path-mini" class="size-6"/>
          </div>
        </div>

        <div class="flex justify-center w-full px-4">
          <.icon name="hero-speaker-wave" class="size-4 mr-2 my-auto"/>
          <form id="volume-slider-form" phx-target={@target} phx-value-group={@id} class="w-11/12">
            <input
              id={["volume-slider", @id]}
              type="range"
              name="volume"
              min="0"
              max="100"
              value={@volume}
              class="w-full"
              phx-hook="volume-change"
            />
          </form>
          <span id="volume-slider-number" class="ml-2">{@volume}</span>
        </div>
      </div>
    </div>
    """
  end

  # TODO rename id -> "group_id"
  attr(:id, :string, required: true)
  attr(:target, :any, required: true)
  attr(:name, :string, required: true)
  attr(:playing, :boolean, required: true)
  attr(:shuffle, :boolean, required: true)
  attr(:continue, :boolean, required: true)
  attr(:volume, :integer, required: true)

  # FIXME dynamically adding a border to the shuf/repeat buttons causes the buttons and volume to the right
  # to shift a pixel. but it looks so much better we are going to leave it for now.

  # TODO it might actually be viable to render a little "1" on top of the repeat icon in the corner
  # to indicate a repeat once mode so I don't have to make a separate icon for it.
  def player_group(assigns) do
    ~H"""
    <div
      class="bg-slate-500 text-white m-2 p-2 rounded-lg border border-slate-600"
      phx-click="view-group"
      phx-target={@target}
      phx-value-group={@id}
    >
      <div class="mx-2">
        <%= @name %>
      </div>

      <div class="flex flex-nowrap gap-2 mx-2 leading-none">
        <div
          phx-click="shuffle"
          phx-target={@target}
          phx-value-group={@id}
          class={["my-auto", @shuffle && "text-slate-500 bg-white rounded-full border border-slate-400 shadow-sm"]}
        >
          <.icon name="icon-shuffle" class="size-6"/>
        </div>

        <div
          phx-click="previous"
          phx-target={@target}
          phx-value-group={@id}
          class="my-auto"
        >
          <.icon name="hero-backward" class="size-6"/>
        </div>

        <div :if={!@playing} phx-click="play" phx-target={@target} phx-value-group={@id}>
          <.icon name="hero-play-solid" class="size-10" />
        </div>

        <div :if={@playing} phx-click="pause" phx-target={@target} phx-value-group={@id}>
          <.icon name="hero-pause-solid" class="size-10" />
        </div>

        <div
          phx-click="next"
          phx-target={@target}
          phx-value-group={@id}
          class="my-auto"
        >
          <.icon name="hero-forward" class="size-6"/>
        </div>

        <div
          phx-click="continue"
          phx-target={@target}
          phx-value-group={@id}
          class={["my-auto", @continue && "text-slate-500 bg-white rounded-full border border-slate-400 shadow-sm"]}
        >
          <.icon name="hero-arrow-path-mini" class="size-6"/>
        </div>

        <form phx-target={@target} phx-value-group={@id}>
          <input
            type="range"
            name="volume"
            min="0"
            max="100"
            value={@volume}
            class="ml-2 w-full"
            phx-change="volume"
            phx-click={JS.dispatch("phx:click-ignore")}
        />
        </form>
      </div>

    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:target, :any, required: true)
  attr(:song, :string)
  attr(:artist, :string)

  attr(:button_class, :string,
    default: "p-1 rounded-lg mx-1 border-2 bg-slate-400 border-slate-500"
  )

  def song_operations_modal(assigns) do
    ~H"""
    <.modal
      id={@id}
    >
      <div class="bg-slate-500 text-white p-2 rounded-lg border border-slate-600 text-white">
        <div class="text-lg font-bold"><%= @song %></div>
        <div class="mb-2 text-normal text-slate-300"><%= @artist %></div>
        <div class="flex flex-row flex-wrap text-xs">
          <div class={@button_class} target={@target} phx-click="play-now" phx-target={@target}>Play now</div>
          <div class={@button_class} target={@target} phx-click="play-next" phx-target={@target}>Play next</div>
          <div class={@button_class} target={@target} phx-click="add-to-playlist" phx-target={@target}>Add to playlist</div>
          <div class={@button_class} target={@target} phx-click="remove-from-queue" phx-target={@target}>Remove from queue</div>
        </div>
      </div>
    </.modal>
    """
  end
end
