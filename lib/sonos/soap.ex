defmodule Sonos.Soap do
  require Logger

  defmodule Request do
    alias Sonos.Soap

    defstruct action: nil, body: nil, route: nil

    def new(service, action, args \\ [], _opts \\ []) do
      Logger.info("request #{service} #{action} #{inspect(args)}")
      route = "#{service}/Control"

      # eg /MediaRenderer/AVTransport -> AVTransport
      service_part = Regex.replace(~r/.*\//, service, "")

      %Request{
        route: route,
        action: Soap.upnp_action(service_part, action),
        body: Soap.upnp_body(service_part, action, args)
      }
    end
  end

  defmodule Response do
    defstruct outputs: nil

    def new(response, function, outputs \\ [], _opts \\ []) do
      case response do
        {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
          result_outputs =
            body
            |> XmlToMap.naive_map()
            |> get_in(["s:Envelope", "#content", "s:Body", "u:#{function}Response"])

          resp = %Response{
            outputs:
              outputs
              |> Enum.map(fn x ->
                result_output = result_outputs |> get_in([to_string(x.original_name)])

                result_output =
                  case !is_nil(result_output) and x.data_type do
                    :string ->
                      result_output

                    :boolean ->
                      result_output |> String.to_existing_atom()

                    x when x in [:i1, :i2, :i4, :i8, :ui1, :ui2, :ui4, :ui8] ->
                      result_output |> String.to_integer()

                    _ ->
                      result_output
                  end

                {
                  x.name,
                  result_output
                }
              end)
              |> Map.new()
          }

          {:ok, resp}

        {:ok, %HTTPoison.Response{body: body, status_code: code}} ->
          IO.puts("error #{inspect(code)}")
          {:error, {:http_error, code, body}}

        err ->
          err
      end
    end
  end

  defmodule Subscription do
    defstruct route: nil

    def new(service) do
      route = "#{service}/Event"

      %Subscription{
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

  def request(%Request{} = req, endpoint, _opts \\ []) do
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

  def subscribe(%Subscription{} = sub, endpoint, our_event_address, _opts \\ []) do
    url = "#{endpoint}/#{sub.route |> String.trim_leading("/")}"

    headers = [
      {"TIMEOUT", "Second-60"},
      {"CALLBACK", "<#{our_event_address}/events/av>"},
      {"NT", "upnp:event"}
    ]

    HTTPoison.request(:subscribe, url, "", headers)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: ""} = resp} ->
        resp.headers
        |> Enum.find(fn {h, _v} ->
          h |> String.upcase() == "SID"
        end)
        |> case do
          nil -> {:ok, :unknown_sid}
          {_h, sid} -> {:ok, sid |> String.trim()}
        end

      err ->
        Logger.error("Failed to subscribe #{inspect(sub)} error #{inspect(err)}")
        {:error, err}
    end
  end
end
