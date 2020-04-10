defmodule Sonos.Commands do

  defmodule Command do
    defstruct action: nil, body: nil
  end

  def play do
    %Command {
      action: "urn:schemas-upnp-org:service:AVTransport:1#Play",
      body: "<u:Play xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><InstanceID>0</InstanceID><Speed>1</Speed></u:Play>"
    }
  end
  def pause do
    %Command {
      action: "urn:schemas-upnp-org:service:AVTransport:1#Pause",
      body: "<u:Pause xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><InstanceID>0</InstanceID></u:Pause>"
    }
  end


  def stop do
    %Command {
      action: "urn:schemas-upnp-org:service:AVTransport:1#Stop",
      body: "<u:Stop xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><InstanceID>0</InstanceID></u:Stop>"
    }
  end

  def next do
    %Command{ 
      action: :"urn:schemas-upnp-org:service:AVTransport:1#Next",
      body: "<u:Next xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"><InstanceID>0</InstanceID></u:Next>"
    }
  end

  def prev do
    :"urn:schemas-upnp-org:service:AVTransport:1#Previous"
  end

  def list_available_services do
    %Command {
      action: "urn:schemas-upnp-org:service:MusicServices:1#ListAvailableServices",
      body: "<u:ListAvailableServices xmlns:u=\"urn:schemas-upnp-org:service:MusicServices:1\"></u:ListAvailableServices>"
    }
  end

  # http://${info.ip}:1400/ZoneGroupTopology/Event
  # `${anyPlayer.baseUrl}/MusicServices/Control`, soap.TYPE.ListAvailableServices)


  def monitor(url \\ "http://192.168.1.97:1400/ZoneGroupToplogy/Event") do
    # TODO get and store SID
        headers = [
          {"TIMEOUT", "Second-60"},
          {"CALLBACK", "<http://192.168.1.80:4001/>"},
          {"NT", "upnp:event"}
        ]
    HTTPoison.get(url, headers)
  end

  def request(url \\ "http://192.168.1.97:1400/MediaRenderer/AVTransport/Control", %Command{} = command) do

    body = """
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>#{command.body}</s:Body></s:Envelope>
    """ |> String.trim

    headers = [
      {"CONTENT-TYPE", "text/xml; charset=\"utf-8\""},
      {"SOAPACTION", "#{command.action}"},
      {"CONTENT_LENGTH", "#{body |> String.length}"},
    ]
    HTTPoison.post(url, body, headers)
  end
end
