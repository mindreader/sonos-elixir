defmodule Sonos.Commands do
#  require Logger
#
#  # /MediaRenderer/AVTransport/Control - play / stop / seek / playlists
#  # /MediaRenderer/Queue/Control - control the queue
#  #   Q:0,4 - queue name, size of queue?
#  # /MediaRenderer/RenderingControl/Control - playback rendering, bass, treble, volume and eq InstanceID?
#  # /MediaRenderer/GroupRenderingControl/Control - control group volume etc.
#  # /MediaServer/ContentDirectory/Control - browsing, searching, listing available music
#  # /HTControl ???  (only beam and playbar, remote control?)
#  # /QPlay ??? (some chinese tencent audio service)
#  #
#  # /ZonePlayer/ ... ?
#  # /AlarmClock - alarm clock functionality
#  # /MusicServices - music serve list etc.
#  # /DeviceProperties - a lot of device properties
#  # /SystemProperties - account stuff, oauth stuff?
#  # /GroupManagement - adding / removing members of groups?
#  # /ZoneGroupTopology - zone groups, but also other stuff? sends useful events
#
#  # not needed?
#  # /MediaRenderer/ConnectionManager/Control - connection manager?
#  # /MediaServer/ConnectionManager/Control - connection manager?
#
#  def play(%Sonos.Device{} = device, speed \\ 1) do
#    device
#    |> avtransport_control("Play", InstanceID: 0, Speed: speed)
#    |> case do
#      {:ok, _res} -> :ok
#    end
#  end
#
#  def pause(%Sonos.Device{} = device) do
#    device
#    |> avtransport_control("Pause", InstanceID: 0)
#    |> case do
#      {:ok, _res} ->
#        :ok
#
#      {:error, {:upnp_error, 701}} ->
#        # most likely tried to pause something that wasn't playing.
#        Logger.debug("Tried to pause something that wasn't playing (error 701)")
#        :ok
#
#      err ->
#        err
#    end
#  end
#
#  def stop(%Sonos.Device{} = device) do
#    device
#    |> avtransport_control("Stop", InstanceID: 0)
#    |> case do
#      {:ok, _res} -> :ok
#      err -> err
#    end
#  end
#
#  def next(%Sonos.Device{} = device) do
#    device
#    |> avtransport_control("Next", InstanceID: 0)
#    |> case do
#      {:ok, _res} ->
#        :ok
#
#      {:error, {:upnp_error, 701}} ->
#        # audio stream doesn't support next (ie radio)
#        Logger.debug("Cannot use next on this type of stream")
#
#      {:error, {:upnp_error, 711}} ->
#        # most likely tried to next when there is no next
#        Logger.debug("Tried to next when no next (error 711)")
#        :ok
#
#      err ->
#        err
#    end
#  end
#
#  def prev(%Sonos.Device{} = device) do
#    device
#    |> avtransport_control("Previous", InstanceID: 0)
#    |> case do
#      {:ok, _res} ->
#        :ok
#
#      {:error, {:upnp_error, 701}} ->
#        # audio stream doesn't support next (ie radio)
#        Logger.debug("Cannot prev on this type of stream")
#        :ok
#
#      {:error, {:upnp_error, 711}} ->
#        # most likely tried to prev when there is no prev
#        Logger.debug("Tried to prev there is no prev (error 711)")
#        :ok
#
#      err ->
#        err
#    end
#  end
#
#  def get_volume(%Sonos.Device{} = device) do
#    import SweetXml
#
#    device
#    |> mediarenderer_control("GetVolume", InstanceID: 0, Channel: :Master)
#    |> case do
#      {:ok, resp} ->
#        resp
#        |> xpath(~x"//s:Envelope/s:Body/u:GetVolumeResponse/CurrentVolume/text()"i)
#        |> case do
#          i when is_integer(i) -> {:ok, i}
#          _err -> {:error, {:invalid_volume, resp}}
#        end
#
#      err ->
#        err
#    end
#  end
#
#  def set_volume(%Sonos.Device{} = device, vol, opts \\ []) when is_integer(vol) do
#    {op, volarg} =
#      if opts[:relative] do
#        {"SetRelativeVolume", Adjustment}
#      else
#        {"SetVolume", DesiredVolume}
#      end
#
#    args = [InstanceID: 0, Channel: :Master] |> Keyword.put(volarg, vol)
#
#    device
#    |> mediarenderer_control(op, args)
#    |> case do
#      {:ok, _resp} -> :ok
#      err -> err
#    end
#  end
#
#  def queue_file(%Sonos.Device{} = device, _filename, opts \\ []) do
#    next = (opts[:next] && 1) || 0
#
#    # TODO EnqueuedURIMetaData
#    # likely didl-lite
#    # <TrackMetaData>&lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item id=&quot;-1&quot; parentID=&quot;-1&quot; restricted=&quot;true&quot;&gt;&lt;res protocolInfo=&quot;sonos.com-http:*:application/x-mpegURL:*&quot; duration=&quot;0:03:22&quot;&gt;x-sonosapi-hls-static:ALkSOiGvBu9Xd50awyN8LBjtaazvgj5HTrNL9NPY2xceITlVkzBKwfTYlkknlbJtWnE-cbpG7oAO-9e2QmNoKkc0lh5-sWjJ?sid=284&amp;amp;flags=0&amp;amp;sn=3&lt;/res&gt;&lt;r:streamContent&gt;&lt;/r:streamContent&gt;&lt;upnp:albumArtURI&gt;/getaa?s=1&amp;amp;u=x-sonosapi-hls-static%3aALkSOiGvBu9Xd50awyN8LBjtaazvgj5HTrNL9NPY2xceITlVkzBKwfTYlkknlbJtWnE-cbpG7oAO-9e2QmNoKkc0lh5-sWjJ%3fsid%3d284%26flags%3d0%26sn%3d3&lt;/upnp:albumArtURI&gt;&lt;dc:title&gt;Blinding Lights&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;dc:creator&gt;The Weeknd&lt;/dc:creator&gt;&lt;upnp:album&gt;Blinding Lights&lt;/upnp:album&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</TrackMetaData>
#    url = "http://192.168.1.80:4001/audio/foo.mp3"
#
#    device
#    |> avtransport_control("AddURIToQueue",
#      InstanceID: 0,
#      EnqueuedURI: url,
#      EnqueuedURIMetaData: "",
#      EnqueueAsNext: next |> IO.inspect(label: "next"),
#      DesiredFirstTrackNumberEnqueued: 0
#    )
#  end
#
#  def get_position_info(%Sonos.Device{} = device) do
#    device |> avtransport_control("GetPositionInfo", InstanceID: 0)
#  end
#
#  def av_debug(%Sonos.Device{} = device) do
#    device |> avtransport_control("GetCurrentTransportActions", InstanceID: 0)
#  end
#
#  def mediarenderer_control(%Sonos.Device{} = device, command, args) do
#    endpoint = device |> Sonos.Device.endpoint()
#
#    "/MediaRenderer/RenderingControl"
#    |> Sonos.Soap.Request.new(command, args)
#    |> request(endpoint)
#  end
#
#  def avtransport_control(%Sonos.Device{} = device, command, args) do
#    endpoint = device |> Sonos.Device.endpoint()
#
#    "/MediaRenderer/AVTransport"
#    |> Sonos.Soap.Request.new(command, args)
#    |> request(endpoint)
#  end
#
#  def avtransport_event(%Sonos.Device{} = device) do
#    endpoint = device |> Sonos.Device.endpoint()
#
#    "/MediaRenderer/AVTransport"
#    |> Sonos.Soap.Subscription.new()
#    |> Sonos.Soap.subscribe(endpoint)
#  end
#
#  def request(%Sonos.Soap.Request{} = req, endpoint, _opts \\ []) do
#    import SweetXml
#
#    req
#    |> Sonos.Soap.request(endpoint)
#    |> case do
#      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
#        {:ok, body}
#
#      {:ok, %HTTPoison.Response{status_code: 500, body: body}} ->
#        error_code =
#          body |> xpath(~x"//s:Envelope/s:Body/s:Fault/detail/UPnPError/errorCode/text()"i)
#
#        {:error, {:upnp_error, error_code}}
#
#      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
#        Logger.debug(
#          "Got back response code #{status} body #{body} for #{req.action} on endpoint #{endpoint}"
#        )
#
#        {:error, {:http_error, status, body}}
#
#      {:error, err} ->
#        Logger.debug("Error running request #{inspect(req)} on endpoint #{endpoint}")
#
#        {:error, err}
#    end
#  end
#
#  # http://${info.ip}:1400/ZoneGroupTopology/Event
#  # `${anyPlayer.baseUrl}/MusicServices/Control`, soap.TYPE.ListAvailableServices)
#
#  #  def subscribe_group_rendering_control(endpoint \\ "http://192.168.1.96:1400") do
#  #    "#{endpoint}/MediaRenderer/GroupRenderingControl/Event" |> subscribe()
#  #  end
#  #
#  #  def subscribe_contentdirectory(endpoint \\ "http://192.168.1.97:1400") do
#  #    "#{endpoint}/MediaServer/ContentDirectory/Event" |> subscribe()
#  #  end
#  #
#  #   def subscribe_topology(endpoint \\ "http://192.168.1.97:1400") do
#  #    "#{endpoint}/ZoneGroupTopology/Event" |> subscribe()
#  #  end
end
