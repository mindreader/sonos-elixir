defmodule Sonos.Soap do
  defmodule Request do
    alias Sonos.Soap

    defstruct action: nil, body: nil, route: nil

    def new(service, action, args \\ [], opts \\ []) do
      route = "#{service}/Control"

      # eg /MediaRenderer/AVTransport -> AVTransport
      service_part = Regex.replace(~r/.*\//, service, "")

      %Request {
        route: route,
        action: Soap.upnp_action(service_part, action),
        body: Soap.upnp_body(service_part, action, args)
      }
    end
  end

  defmodule Subscription do
    defstruct route: nil

    def new(service) do
      route = "#{service}/Event"

      %Subscription {
        route: route
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
    XmlBuilder.element(
      "u:#{action}",
      %{
        :"xmlns:u" => upnp_service(service)
      },
      args
      |> Enum.map(fn {k, v} ->
        XmlBuilder.element(k, %{}, v)
      end)
    )
  end

  def envelope(contents) when is_list(contents) do
    XmlBuilder.element(
      :"s:Envelope",
      %{
        :"xmlns:s" => :"http://schemas.xmlsoap.org/soap/envelope/",
        :"s:encodingStyle" => :"http://schemas.xmlsoap.org/soap/encoding/"
      },
      contents
    )
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

  def request(%Request{} = req, endpoint, opts \\ []) do
    url = "#{endpoint}/#{req.route |> String.trim_leading("/")}"

    body = req.body |> body_tag() |> envelope() |> XmlBuilder.generate(format: :none)

    headers =
      [
        {"CONTENT-TYPE", "text/xml; charset=\"utf-8\""},
        {"SOAPACTION", "#{req.action}"},
        {"CONTENT_LENGTH", "#{body |> String.length()}"}
      ]

    HTTPoison.post(url, body, headers)
  end

  def subscribe(%Subscription{} = sub, endpoint, _opts \\ []) do
    # TODO get and store SID
    url = "#{endpoint}/#{sub.route |> String.trim_leading("/")}"

    headers = [
      {"TIMEOUT", "Second-60"},
      {"CALLBACK", "<http://192.168.1.80:4001/>"},
      {"NT", "upnp:event"}
    ]

    HTTPoison.request(:subscribe, url, "", headers)
  end
end
