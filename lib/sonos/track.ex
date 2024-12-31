defmodule Sonos.Track do
  alias Sonos.Playlist

  @doc """
  A track is a single song or video of stream. We need to be able to parse and create them in
  order to add tracks to the queue, and each blob of xml could represent one or more tracks,
  it is down to context to determine how to interpret them.

  Because tracks are constantly fetched from the devices, this is the canonical "Track" record
  in the application. Sonos.Schema.Track is the database layout, and conversions must happen
  manually.
  """

  defmodule Content do
    @doc """
    The inner content of a didl item.
    """
    defstruct url: nil, protocol_info: nil, duration: nil

    def to_xml(%Content{url: url, protocol_info: protocol_info, duration: duration}) do
      attributes =
        %{
          :protocolInfo => protocol_info,
          :duration => duration
        }
        |> Enum.filter(fn {_k, v} -> v end)
        |> Map.new()

      XmlBuilder.element(:res, attributes, [url])
    end

    def parse(xml) do
      xml
      |> Sonos.Utils.naive_map()
      |> then(&new/1)
    end

    def new(obj) when is_map(obj) do
      %Content{
        url: obj["#content"],
        protocol_info: obj["-protocolInfo"],
        duration: obj["-duration"]
      }
    end
  end

  defstruct content: nil,
            creator: nil,
            album: nil,
            title: nil,
            art: nil,
            class: nil,
            id: nil,
            parent_id: nil,
            restricted: nil

  @doc """
  Useful when you know there will only ever be one track, such as the currently playing track,
  or the next one in the queue.
  """
  def parse_single(xml) do
    xml
    |> Sonos.Utils.naive_map()
    |> then(fn json ->
      get_in(json, ["DIDL-Lite", "item"])
      |> then(&new/1)
    end)
  end

  @doc """
  Useful when you know there will be multiple tracks, such as the queue, or in a playlist. If there happens
  to be only a single track, we can't detect it from the xml only so this will coerce it into a list
  with a single item.
  """
  def parse_list(xml) do
    xml
    |> Sonos.Utils.naive_map()
    |> then(fn json ->
      get_in(json, ["DIDL-Lite", "item"])
      |> Sonos.Utils.coerce_to_list()
      |> Enum.map(&new/1)
    end)
  end

  def new(nil), do: nil

  def new(xs) when is_list(xs) do
    raise "expected a single track, got a list of tracks, use parse_list instead"
  end

  def new(obj) when is_map(obj) do
    %Sonos.Track{
      content: Content.new(obj["#content"]["res"]),
      creator: obj["#content"]["dc:creator"],
      album: obj["#content"]["upnp:album"],
      title: obj["#content"]["dc:title"],
      art: obj["#content"]["upnp:albumArtURI"],
      class: obj["#content"]["upnp:class"],
      id: obj["-id"],
      parent_id: obj["-parentID"],
      restricted: obj["-restricted"]
    }
  end

  def to_xml(%Sonos.Track{} = track) do
    to_xml([track])
  end

  def to_xml([%Sonos.Track{} | _] = tracks) do
    ns = %{
      :"xmlns:dc" => "http://purl.org/dc/elements/1.1/",
      :"xmlns:upnp" => "urn:schemas-upnp-org:metadata-1-0/upnp/",
      :"xmlns:r" => "urn:schemas-rinconnetworks-com:metadata-1-0/",
      :xmlns => "urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"
    }

    XmlBuilder.element(
      :"DIDL-Lite",
      ns,
      tracks
      |> Enum.map(fn %Sonos.Track{} = track ->
        item_attributes = %{
          :id => track.id,
          :parentID => track.parent_id,
          :restricted => track.restricted
        }

        XmlBuilder.element(
          :item,
          item_attributes,
          [
            Content.to_xml(track.content),
            track.creator && XmlBuilder.element(:"dc:creator", track.creator),
            track.title && XmlBuilder.element(:"dc:title", track.title),
            track.album && XmlBuilder.element(:"upnp:album", track.album),
            track.art && XmlBuilder.element(:"upnp:albumArtURI", track.art),
            track.class && XmlBuilder.element(:"upnp:class", track.class)
          ]
          |> Enum.filter(& &1)
        )
      end)
    )
  end

  def persist(%Sonos.Track{} = track) do
    %{
      url: track.content.url,
      protocol_info: track.content.protocol_info,
      duration: track.content.duration |> Sonos.Utils.time_to_sec(),
      creator: track.creator,
      album: track.album,
      title: track.title,
      art: track.art,
      class: track.class,
      item_id: track.id,
      parent_id: track.parent_id,
      restricted: track.restricted
    }
    |> Sonos.Schema.Track.replace_track()
  end

  def from_schema(%Sonos.Schema.Track{} = track) do
    %Sonos.Track{
      content: %Content{
        url: track.url,
        protocol_info: track.protocol_info,
        duration: track.duration |> Sonos.Utils.sec_to_time()
      },
      creator: track.creator,
      album: track.album,
      title: track.title,
      art: track.art,
      class: track.class,
      id: track.item_id,
      parent_id: track.parent_id,
      restricted: track.restricted |> to_string()
    }
  end

  def stream(playlist, opts \\ [])

  def stream(%Playlist{} = playlist, opts) do
    [playlist] |> stream(opts)
  end

  def stream([%Playlist{} | _] = playlists, _opts) do
    import Ecto.Query

    playlist_ids = playlists |> Enum.map(& &1.id) |> Enum.uniq()

    Sonos.Schema.Track.query()
    |> where([playlists: pl], pl.id in ^playlist_ids)
    |> order_by(desc: :inserted_at)
    |> Sonos.Repo.stream()
  end
end
