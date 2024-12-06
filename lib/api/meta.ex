defmodule Sonos.Api.Meta do
  @doc """
   Turn an URN like "urn:schemas-upnp-org:device:ZonePlayer:1" into something usable like "ZonePlayer"
  """
  def type_from_urn(urn) do
    urn
    |> String.split(":")
    |> Enum.reverse()
    |> Enum.drop_while(fn piece -> piece |> Integer.parse() != :error end)
    |> hd
  end

  @doc """
  Extracts device types and their associated service types from JSON device data.

  Takes JSON data containing device and service information and a parent module.
  Returns a list of tuples containing:
  - Device type as a module name (with parent module prepended)
  - List of service type atoms derived from the service URNs

  ## Parameters
    - json: List of device maps containing "type" and "services" keys
    - parent_module: Parent module to use for device type module names

  ## Example
      json = [
        %{
          "type" => "urn:schemas-upnp-org:device:ZonePlayer:1",
          "services" => [
            %{"type" => "urn:schemas-upnp-org:service:AVTransport:1"}
          ]
        }
      ]
      service_types(json, MyApp)
      #=> [{D.F.ZonePlayer, [:av_transport]}]
  """
  def service_types(json, parent_module) do
      json
      |> Enum.map(fn x ->
        {x["type"], x["services"]}
      end)
      |> Enum.map(fn {dev_urn, services} ->
        dev_type =
          dev_urn
          |> type_from_urn()
          |> then(fn mod ->
            Module.concat(parent_module, mod)
          end)

        service_types =
          services
          |> Enum.map(fn x -> x["type"] end)
          |> Enum.map(fn urn ->
            urn
            |> type_from_urn()
            |> Macro.underscore()
            |> String.to_atom()
          end)

        {dev_type, service_types}
      end)
  end

  defmacro define_device(name, data) do
    filename =
      quote do
        unquote(data)
      end
      |> Macro.expand(__ENV__)

    json = File.read!(filename) |> Jason.decode!()

    service_types = json |> service_types(__CALLER__.module)

    name = quote do def name do unquote(name) end end

    devices = service_types |> Enum.map(fn {dev_type, service_types} ->
      Sonos.Api.Meta.device_entry(dev_type, service_types)
    end)

    [ name | devices ]
  end

  def device_entry(dev_type, service_types) do
    functions =
      service_types
      |> Enum.map(fn x ->
        quote do
          def unquote(x)() do
            nil
          end
        end
      end)

    quote do
      defmodule unquote(dev_type) do
        unquote(functions)
      end
    end
  end
end
