defmodule Sonos.Soap do
  require Logger

  defmodule Control do
    defstruct control_url: nil, service_type: nil, action: nil, args: nil

    def new(control_url, service_type, action, args \\ [], _opts \\ []) do
      %Control{
        control_url: control_url,
        service_type: service_type,
        action: action,
        args: args
      }
    end
  end

  defmodule Subscribe do
    defstruct events_url: nil, our_event_address: nil, timeout: nil

    @default_timeout :timer.seconds(5 * 60)

    def new(events_url, our_event_address, opts \\ []) do
      timeout = opts[:timeout] || @default_timeout

      # The event address is too long if we have all this upnp stuff in it,
      # causing many services to be truncated when we get back notify requests.
      our_event_address =
        our_event_address
        |> String.replace("::urn:schemas-upnp-org:device:ZonePlayer:1", "")

      %Subscribe{
        events_url: events_url,
        our_event_address: our_event_address,
        timeout: timeout
      }
    end
  end

  defmodule Resubscribe do
    defstruct events_url: nil, sid: nil, timeout: nil

    @default_timeout :timer.seconds(5 * 60)

    def new(events_url, sid, opts \\ []) do
      timeout = opts[:timeout] || @default_timeout

      %Resubscribe{
        events_url: events_url,
        sid: sid,
        timeout: timeout
      }
    end
  end

  def response(response, function, outputs \\ [], _opts \\ []) do
    case response do
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
        result_outputs =
          body
          |> XmlToMap.naive_map()
          |> get_in(["s:Envelope", "#content", "s:Body", "u:#{function}Response"])

        resp = %{
          outputs:
            outputs
            |> Enum.map(fn x ->
              result_output = result_outputs |> get_in([to_string(x.original_name)])
              result_output = Sonos.Utils.coerce_data_type(result_output, x.data_type)

              {
                x.name,
                result_output
              }
            end)
            |> Map.new()
        }

        {:ok, resp}

      {:ok, %HTTPoison.Response{body: body, status_code: code}} ->
        {:error, {:http_error, code, body}}

      err ->
        err
    end
  end

  defmodule Notification do
  end

  defp element(contents, name, attrs \\ %{}) do
    # WHy did the author write this so non idiomatically?
    XmlBuilder.element(name, attrs, contents)
  end

  def envelope(contents) when is_list(contents) do
    contents
    |> element(:"s:Envelope", %{
      :"xmlns:s" => :"http://schemas.xmlsoap.org/soap/envelope/",
      :"s:encodingStyle" => :"http://schemas.xmlsoap.org/soap/encoding/"
    })
  end

  def envelope(contents) do
    [contents] |> envelope()
  end

  def body_tag(contents) when is_list(contents) do
    contents |> element(:"s:Body", %{})
  end

  def body_tag(contents) do
    [contents] |> body_tag()
  end

  def request(req, endpoint, _opts \\ [])

  def request(%Control{} = req, endpoint, _opts) do
    url = "#{endpoint}#{req.control_url}"
    action = "#{req.service_type}##{req.action}"

    # During normal operation, the fewer of these the better.
    Logger.info("requesting action #{action} on endpoint #{endpoint}")

    body =
      req.args
      |> Enum.map(fn {k, v} ->
        v |> element(k)
      end)
      |> element(:"u:#{req.action}", %{
        :"xmlns:u" => req.service_type
      })
      |> body_tag()
      |> envelope()
      |> XmlBuilder.generate(format: :none)

    headers =
      [
        {"CONTENT-TYPE", "text/xml; charset=\"utf-8\""},
        {"SOAPACTION", "#{action}"},
        {"CONTENT_LENGTH", "#{body |> String.length()}"}
      ]

    HTTPoison.post(url, body, headers)
  end

  def request(%Subscribe{} = sub, endpoint, opts) do
    timeout = opts[:timeout] || sub.timeout || 60 * 5

    url = "#{endpoint}#{sub.events_url}"

    uri = url |> URI.parse()

    headers = [
      {"TIMEOUT", "Second-#{timeout}"},
      {"HOST", "#{uri.host}:#{uri.port}"},
      {"USER_AGENT", "Sonos-Elixir"},
      {"CALLBACK", "<#{sub.our_event_address}>"},
      {"NT", "upnp:event"}
    ]

    HTTPoison.request(:subscribe, url, "", headers)
  end

  def request(%Resubscribe{} = resub, endpoint, opts) do
    timeout = opts[:timeout] || resub.timeout || 60 * 5
    url = "#{endpoint}#{resub.events_url}"
    uri = url |> URI.parse()

    headers = [
      {"SID", resub.sid},
      {"TIMEOUT", "Second-#{timeout}"},
      {"HOST", "#{uri.host}:#{uri.port}"}
    ]

    HTTPoison.request(:subscribe, url, "", headers)
  end
end
