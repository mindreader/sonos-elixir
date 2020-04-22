defmodule Sonos.Commands do
  require Logger

  # /MediaRenderer/AVTransport/Control - play / stop / seek / playlists
  # /MediaRenderer/Queue/Control - control the queue
  # /MediaRenderer/RenderingControl/Control - playback rendering, bass, treble, volume and eq InstanceID?
  # /MediaRenderer/GroupRenderingControl/Control - control group volume etc.
  # /MediaServer/ContentDirectory/Control - browsing, searching, listing available music
  # /HTControl ???  (only beam and playbar, remote control?)
  # /QPlay ??? (some chinese tencent audio service)
  #
  # /ZonePlayer/ ... ?
  # /AlarmClock - alarm clock functionality 
  # /MusicServices - music serve list etc.
  # /DeviceProperties - a lot of device properties
  # /SystemProperties - account stuff, oauth stuff?
  # /GroupManagement - adding / removing members of groups?
  # /ZoneGroupTopology - zone groups, but also other stuff? sends useful events

  # not needed?
  # /MediaRenderer/ConnectionManager/Control - connection manager?
  # /MediaServer/ConnectionManager/Control - connection manager?

  def play(%Sonos.Device{} = device, speed \\ 1) do
    device
    |> avtransport_control("Play", InstanceID: 0, Speed: speed)
    |> case do
      {:ok, _res} -> :ok
    end
  end

  def pause(%Sonos.Device{} = device) do
    device
    |> avtransport_control("Pause", InstanceID: 0)
    |> case do
      {:ok, _res} ->
        :ok

      {:error, {:upnp_error, 701}} ->
        # most likely tried to pause something that wasn't playing.
        Logger.debug("Tried to pause something that wasn't playing (error 701)")
        :ok

      err ->
        err
    end
  end

  def stop(%Sonos.Device{} = device) do
    device
    |> avtransport_control("Stop", InstanceID: 0)
    |> case do
      {:ok, _res} -> :ok
      err -> err
    end
  end

  def next(%Sonos.Device{} = device) do
    device
    |> avtransport_control("Next", InstanceID: 0)
    |> case do
      {:ok, _res} ->
        :ok

      {:error, {:upnp_error, 701}} ->
        # audio stream doesn't support next (ie radio)
        Logger.debug("Cannot prev on this type of stream")


      {:error, {:upnp_error, 711}} ->
        # most likely tried to next when there is no next
        Logger.debug("Tried to next when no next (error 711)")
        :ok

      err ->
        err
    end
  end

  def prev(%Sonos.Device{} = device) do
    device
    |> avtransport_control("Previous", InstanceID: 0)
    |> case do
      {:ok, _res} -> :ok
      {:error, {:upnp_error, 701}} ->
        # audio stream doesn't support next (ie radio)
        Logger.debug("Cannot prev on this type of stream")
        :ok

      {:error, {:upnp_error, 711}} ->
        # most likely tried to prev when there is no prev
        Logger.debug("Tried to prev there is no prev (error 711)")
        :ok

      err -> err
    end
  end

  def avtransport_control(%Sonos.Device{} = device, command, args) do
    import SweetXml

    Sonos.Soap.Request.new("/MediaRenderer/AVTransport", command, args, control: true)
    |> Sonos.Soap.request(device |> Sonos.Device.endpoint())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: 500, body: body}} ->
        error_code =
          body |> xpath(~x"//s:Envelope/s:Body/s:Fault/detail/UPnPError/errorCode/text()"i)

        {:error, {:upnp_error, error_code, error_message}}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.debug(
          "Got back response code #{status} body #{body} for #{command} on #{inspect(device)}"
        )

        {:error, {:http_error, status, body}}

      {:error, err} ->
        Logger.debug(
          "Error running command #{command} #{inspect(args)} on device #{inspect(device)}"
        )

        {:error, err}
    end
  end

  # def list_available_services do
  #    %Command{
  #      action: "urn:schemas-upnp-org:service:MusicServices:1#ListAvailableServices",
  #      body:
  #        "<u:ListAvailableServices xmlns:u=\"urn:schemas-upnp-org:service:MusicServices:1\"></u:ListAvailableServices>"
  #    }
  #  end

  # http://${info.ip}:1400/ZoneGroupTopology/Event
  # `${anyPlayer.baseUrl}/MusicServices/Control`, soap.TYPE.ListAvailableServices)

  def subscribe_group_rendering_control(endpoint \\ "http://192.168.1.96:1400") do
    "#{endpoint}/MediaRenderer/GroupRenderingControl/Event" |> subscribe()
  end

  def subscribe_contentdirectory(endpoint \\ "http://192.168.1.97:1400") do
    "#{endpoint}/MediaServer/ContentDirectory/Event" |> subscribe()
  end

  def subscribe_av_transport(endpoint \\ "http://192.168.1.97:1400") do
    "#{endpoint}/MediaRenderer/AVTransport/Event" |> subscribe()
  end

  def subscribe_topology(endpoint \\ "http://192.168.1.97:1400") do
    "#{endpoint}/ZoneGroupTopology/Event" |> subscribe()
  end

  def subscribe(url) do
    # TODO get and store SID
    # TODO don't hard code ip
    headers = [
      {"TIMEOUT", "Second-60"},
      {"CALLBACK", "<http://192.168.1.80:4001/>"},
      {"NT", "upnp:event"}
    ]

    HTTPoison.request(:subscribe, url, "", headers)
  end
end
