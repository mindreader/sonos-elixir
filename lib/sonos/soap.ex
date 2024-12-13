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

    # TODO longer for prod.
    @default_timeout :timer.seconds(60)

    def new(events_url, our_event_address, opts \\ []) do
      timeout = opts[:timeout] || @default_timeout

      %Subscribe{
        events_url: events_url,
        our_event_address: our_event_address,
        timeout: div(timeout, 1000)
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

    body = req.args
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

  def request(%Subscribe{} = sub, endpoint, _opts) do
    url = "#{endpoint}#{sub.events_url}"
    headers = [
      {"TIMEOUT", "Second-#{sub.timeout}"},
      {"CALLBACK", "<#{sub.our_event_address}>"},
      {"NT", "upnp:event"}
    ]

    HTTPoison.request(:subscribe, url, "", headers)
  end

  def subscribe(endpoint, events_url, our_event_address, _opts \\ []) do
    url = "#{endpoint}#{events_url}"

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
        Logger.error("Failed to subscribe #{inspect(url)} error #{inspect(err)}")
        {:error, err}
    end
  end
end
