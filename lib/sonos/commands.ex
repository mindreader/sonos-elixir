defmodule Sonos.Commands do
  defmodule Command do
    defstruct action: nil, body: nil
  end

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

  def play2 do
    %Command{
      action: "urn:schemas-upnp-org:service:AVTransport:1#Play",
      body:
        "<u:Play xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><InstanceID>0</InstanceID><Speed>1</Speed></u:Play>"
    }
  end

  def play(%Sonos.Device{} = device) do
    Sonos.Soap.Request.new("AVTransport", "Play", [InstanceID: 0])
    |> Sonos.Soap.request(device |> Sonos.Device.endpoint())
  end

  def pause do
    %Command{
      action: "urn:schemas-upnp-org:service:AVTransport:1#Pause",
      body:
        "<u:Pause xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><InstanceID>0</InstanceID></u:Pause>"
    }
  end

  def stop do
    %Command{
      action: "urn:schemas-upnp-org:service:AVTransport:1#Stop",
      body:
        "<u:Stop xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><InstanceID>0</InstanceID></u:Stop>"
    }
  end

  def next do
    %Command{
      action: :"urn:schemas-upnp-org:service:AVTransport:1#Next",
      body:
        "<u:Next xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><InstanceID>0</InstanceID></u:Next>"
    }
  end

  def prev do
    :"urn:schemas-upnp-org:service:AVTransport:1#Previous"
  end

  def list_available_services do
    %Command{
      action: "urn:schemas-upnp-org:service:MusicServices:1#ListAvailableServices",
      body:
        "<u:ListAvailableServices xmlns:u=\"urn:schemas-upnp-org:service:MusicServices:1\"></u:ListAvailableServices>"
    }
  end

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
