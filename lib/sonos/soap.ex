defmodule Sonos.Soap do

  defmodule Request do
    alias Sonos.Soap

    defstruct action: nil, body: nil, route: nil

    def new(service, action, args \\ [], opts \\ []) do
      route = cond do
        opts[:control] -> "#{service}/Control"
        opts[:event] -> "#{service}/Event"
        true -> service
      end

      # eg /MediaRenderer/AVTransport -> AVTransport
      service_part = Regex.replace(~r/.*\//, service,"")

      %Request{
        route: route,
        action: Soap.upnp_action(service_part, action),
        body: Soap.upnp_body(service_part, action, args)
      }
    end
  end

  def upnp_service(service) do
    "urn:schemas-upnp-org:service:#{service}:1"
  end

  def upnp_action(service, action) do
    "#{upnp_service(service)}##{action}"
  end

  def upnp_body(service, action, args) do
    XmlBuilder.element("u:#{action}", %{
      :"xmlns:u" => upnp_service(service)
    }, args |> Enum.map(fn {k, v} ->
      XmlBuilder.element(k, %{}, v)
    end))
  end


  def envelope(contents) when is_list(contents) do
    XmlBuilder.element(:"s:Envelope", %{:"xmlns:s" => :"http://schemas.xmlsoap.org/soap/envelope/", :"s:encodingStyle" => :"http://schemas.xmlsoap.org/soap/encoding/"}, contents)
  end

  def envelope(contents) do
    [contents] |> envelope()
  end

  def body_tag(contents) when is_list(contents) do
    XmlBuilder.element(:"s:Body", %{}, contents)
  end

  def body_tag(contents) do
    [contents] |> body_tag()
  end

  def request(%Request{} = req, endpoint) do
    url = "#{endpoint}/#{req.route |> String.trim_leading("/")}"

    body = req.body |> body_tag() |> envelope() |> XmlBuilder.generate(format: :none)

    headers = [
      {"CONTENT-TYPE", "text/xml; charset=\"utf-8\""},
      {"SOAPACTION", "#{req.action}"},
      {"CONTENT_LENGTH", "#{body |> String.length()}"}
    ]

    HTTPoison.post(url, body, headers)
  end
end
