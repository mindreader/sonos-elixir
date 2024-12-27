defmodule SonosWeb.PlayerComponents do
  @moduledoc """
  Reusable components for the player itself.
  """

  import SonosWeb.CoreComponents

  use Phoenix.Component

  alias Phoenix.LiveView.JS
  use Gettext, backend: SonosWeb.Gettext

  attr(:target, :any, required: true)
  attr(:queue, :list, required: true)

  # TODO mark current song!

  def player_queue(assigns) do
    ~H"""
    <.table
        id="queue"
        rows={@queue}
        row_id={&elem(&1, 0)}
        row_item={&elem(&1, 1)}
        row_click={fn {id, _} ->
          JS.push("view-song", target: @target, value: %{queue_id: id})
        end}
        row_highlight={fn {_, entry} -> entry.current end}
    >
      <:col :let={entry} label="Index"><%= entry.index %></:col>
      <:col :let={entry} label="Song"><%= entry.song %></:col>
      <:col :let={entry} label="Artist"><%= entry.artist %></:col>
      <:col :let={entry} label="Album"><%= entry.album %></:col>
      <:col :let={entry} label="Duration"><%= entry.track_duration %></:col>
    </.table>
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
end
