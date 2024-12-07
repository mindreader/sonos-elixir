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

        services =
          services
          |> Enum.map(fn x ->
            %{
              module: x["type"]
              |> type_from_urn()
              |> String.to_atom()
              |> then(fn mod ->
                Module.concat(dev_type, mod)
              end),

              functions: x["scpd"]["actions"] |> Enum.map(fn x ->
                x |> IO.inspect(label: "x")

                namef = fn x -> x["name"] |> String.replace("UUIDs", "Uuids") |> Macro.underscore() |> String.to_atom() end
                %{
                name: namef.(x),
                inputs: x["inputs"] |> Enum.map(namef),
                outputs: x["outputs"] |> Enum.map(namef)
              }
              end)
            }
          end)

        %{device: dev_type, services: services}
      end)
  end

  defmacro define_device(name, data) do
    filename =
      quote do
        unquote(data)
      end
      |> Macro.expand(__ENV__)

    json = File.read!(filename) |> Jason.decode!()

    services = json |> service_types(__CALLER__.module)

    name = quote do def name do unquote(name) end end

    devices = services |> Enum.map(fn %{device: dev_type, services: services} ->
      Sonos.Api.Meta.device_entry(dev_type, services)
    end)

    [ name | devices ]
  end

  def device_entry(dev_type, services) do
    functions =
      services
      |> Enum.map(fn %{module: mod} = spec ->

        functions = spec.functions |> Enum.map(fn x -> service_entry(x) end)

        quote do
          defmodule unquote(mod) do
            unquote(functions)
          end
        end
      end)

    quote do
      defmodule unquote(dev_type) do
        unquote(functions)
      end
    end
  end

  def service_entry(service) do
    inputs = service.inputs |> Enum.map(fn x -> x |> Macro.var(nil) end)
    quote do
      def unquote(service.name)(unquote_splicing(inputs)) do
        _ = {unquote_splicing(inputs)}

        unquote(service.outputs) |> Enum.map(fn x -> {x, nil} end)
      end
    end
  end
end
