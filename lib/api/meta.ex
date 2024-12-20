defmodule Sonos.Api.Meta do
  @data_types [:boolean, :string, :ui1, :ui2, :ui4, :i1, :i2, :i4]

  def validate([], outputs) do
    outputs
  end

  def validate(variables, output) do
    validators =
      variables
      |> Enum.map(fn %{name: name, data_type: type} ->
        validator(name, type)
      end)

    quote do
      with unquote_splicing(validators) do
        unquote(output)
      end
    end
  end

  def val_type(true, _varname, _type), do: :ok

  def val_type(false, varname, type) do
    {:error, {:invalid_value, varname, "#{type} required"}}
  end

  def validator(varname, type) when type in @data_types do
    var = Macro.var(varname, nil)

    # TODO richer errors
    case type do
      :boolean ->
        quote do
          :ok <- M.val_type(unquote(var) in [true, false], unquote(varname), unquote(type))
        end

      :string ->
        quote do
          :ok <-
            M.val_type(
              is_binary(unquote(var)) || is_atom(unquote(var)),
              unquote(varname),
              unquote(type)
            )
        end

      :ui1 ->
        # TODO FIXME eg. "<type> between 0 and 255 required"
        quote do
          :ok <-
            M.val_type(
              is_integer(unquote(var)) and unquote(var) >= 0 and unquote(var) <= 255,
              unquote(varname),
              unquote(type)
            )
        end

      :ui2 ->
        quote do
          :ok <-
            M.val_type(
              is_integer(unquote(var)) and unquote(var) >= 0 and unquote(var) <= 65535,
              unquote(varname),
              unquote(type)
            )
        end

      :ui4 ->
        quote do
          :ok <-
            M.val_type(
              is_integer(unquote(var)) and unquote(var) >= 0 and unquote(var) <= 4_294_967_295,
              unquote(varname),
              unquote(type)
            )
        end

      :i1 ->
        quote do
          :ok <-
            M.val_type(
              is_integer(unquote(var)) and unquote(var) >= -128 and unquote(var) <= 127,
              unquote(varname),
              unquote(type)
            )
        end

      :i2 ->
        quote do
          :ok <-
            M.val_type(
              is_integer(unquote(var)) and unquote(var) >= -32768 and unquote(var) <= 32767,
              unquote(varname),
              unquote(type)
            )
        end

      :i4 ->
        quote do
          :ok <-
            M.val_type(
              is_integer(unquote(var)) and unquote(var) >= -2_147_483_648 and
                unquote(var) <= 2_147_483_647,
              unquote(varname),
              unquote(type)
            )
        end
    end
  end

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
  def device_services(json, parent_module) do
    json
    |> Enum.map(fn x ->
      {x["type"], x["services"]}
    end)
    |> Enum.map(fn {dev_urn, services} ->
      dev_name = dev_urn |> type_from_urn() |> String.to_atom()
      dev_module = Module.concat(parent_module, dev_name)

      services =
        services
        |> Enum.map(fn x ->
          state_variables =
            x["scpd"]["state_variables"]
            |> Enum.map(fn {name, info} ->
              # some of these state variables are doubled, a bug?
              [info] = info |> Enum.uniq()
              name = name |> String.to_atom()

              {name,
               %{
                 data_type: info |> Map.get("data_type") |> String.to_atom(),
                 send_events: info |> Map.get("send_events")
               }}
            end)

          service_name =
            x["type"]
            |> type_from_urn()
            |> String.to_atom()

          %{
            name: service_name,
            type: x["type"],
            control_url: x["control_url"],
            event_sub_url: x["events_url"],
            module: Module.concat(dev_module, service_name),
            functions:
              x["scpd"]["actions"]
              |> Enum.map(fn x ->
                dtypef = fn type -> state_variables[type].data_type end

                lowercasef = fn x ->
                  x
                  # functions like "FooUUIDsService" would get changed to "foo_uui_ds_service" by Macro.underscore
                  |> String.replace("UUIDs", "Uuids")
                  |> String.replace("IDs", "Ids")
                  |> Macro.underscore()
                  |> String.to_atom()
                end

                variablef = fn x ->
                  %{
                    name: x["name"] |> lowercasef.(),
                    original_name: x["name"] |> String.to_atom(),
                    data_type: x["state_variable"] |> String.to_atom() |> dtypef.(),
                    state_variable: x["state_variable"] |> String.to_atom()
                  }
                end

                %{
                  name: x["name"] |> lowercasef.(),
                  original_name: x["name"] |> String.to_atom(),
                  inputs: x["inputs"] |> Enum.map(variablef),
                  outputs: x["outputs"] |> Enum.map(variablef)
                }
              end),
            state_variables: state_variables
          }
        end)

      %{name: dev_name, module: dev_module, services: services}
    end)
  end

  defmacro define_device(name, data, _opts \\ []) do
    filename = data |> Macro.expand(__ENV__)

    json = File.read!(filename) |> Jason.decode!()

    # TODO this is annoying because it is read once for each device rather than once
    # and then shared for all of them. But I'd rather do that than hold it in memory.
    docs = File.read!("data/documentation.json") |> Jason.decode!()

    devices = json |> device_services(__CALLER__.module)

    # @external_resource on this json file to aid in recompilation
    json_resource =
      quote do
        @external_resource unquote(filename)
      end

    # Sonos.Api.<model>.name/0 (the name of the device)
    # eg Sonos.Api.Play1.name/0
    name =
      quote do
        @doc "The name of this device."
        def name do
          unquote(name)
        end
      end

    devices =
      devices
      |> Enum.map(fn %{module: dev_module, services: services} ->
        Sonos.Api.Meta.device_entry(dev_module, services, docs)
      end)

    error_docs =
      docs["errors"]
      |> then(fn errors ->
        if is_list(errors) do
          error_list =
            errors
            |> Enum.map(fn %{"code" => code, "description" => desc} ->
              "* #{code}: #{desc}\n"
            end)

          if error_list != [] do
            quote do
              @moduledoc """
                Module for a Sonos Speaker device.

                ## Known Generic Error Codes

                #{unquote(error_list)}
              """
            end
          end
        end
      end)

    [json_resource, name, error_docs | devices]
  end

  def error_docs(service_docs) do
    service_docs["errors"]
    |> then(fn errors ->
      if is_list(errors) do
        quote do
          unquote("""
          ## Error Codes

          #{errors |> Enum.map(fn %{"code" => code, "description" => desc} -> "* #{code}: #{desc}\n" end) |> Enum.join()}
          """)
        end
      end
    end)
  end

  def device_entry(dev_module, services, docs) do
    # Sonos.Api.<model>.<device>.<service>.<function>
    # eg Sonos.Api.Play1.MediaServer.ConnectionManager.get_protocol_info
    functions =
      services
      |> Enum.map(fn %{module: service_module, name: service_name, type: service_type} = spec ->
        service_docs = docs["services"]["#{service_name}Service"]

        error_docs = docs |> error_docs()

        functions =
          spec.functions
          |> Enum.map(fn function ->
            function_docs = service_docs["actions"][function.original_name |> to_string()]

            function_entry(
              spec.control_url,
              service_module,
              service_type,
              function,
              function_docs
            )
          end)

        event_variables =
          spec.state_variables
          |> Enum.filter(fn {_var, x} -> x.send_events end)
          |> Enum.map(&elem(&1, 0))
          |> Enum.map(&"* #{&1}\n")

        quote do
          defmodule unquote(service_module) do
            alias Sonos.Api.Meta, as: M

            @moduledoc """
            #{unquote(service_docs["description"])}

            #{unquote(error_docs)}
            """

            unquote(functions)

            @doc """
              Subscribe to events from this service.

              ## Parameters
              * `endpoint`: The endpoint of the device to call (eg "http://192.168.1.96:1400")


              ## Options
              * `timeout`: The timeout for the subscription (default 60 seconds)


              ## Variables
              #{unquote(event_variables)}
            """
            def subscribe(endpoint, event_address, opts \\ []) do
              sub =
                Sonos.Soap.Subscribe.new(
                  unquote(spec.event_sub_url),
                  event_address,
                  opts
                )

              sub |> Sonos.Soap.request(endpoint)
            end

            def resubscribe(endpoint, sid, opts \\ []) do
              resub =
                Sonos.Soap.Resubscribe.new(
                  unquote(spec.event_sub_url),
                  sid,
                  opts
                )

              resub |> Sonos.Soap.request(endpoint)
            end

            @doc """
            The upnp service type for this service. Useful for subscribing to events.
            """
            def service_type do
              unquote(service_type)
            end

            def short_service_type do
              unquote(service_type |> String.replace("urn:schemas-upnp-org:service:", ""))
            end
          end
        end
      end)

    # Sonos.Api.<model>.<device>
    quote do
      defmodule unquote(dev_module) do
        unquote(functions)
      end
    end
  end

  def function_entry(control_url, service_module, service_type, action, function_docs) do
    inputs = action.inputs |> Enum.map(fn x -> {x.original_name, Macro.var(x.name, nil)} end)
    endpoint = Macro.var(:endpoint, nil)

    soap_fetch =
      quote do
        Sonos.Soap.Control.new(
          unquote(control_url),
          unquote(service_type),
          unquote(action.original_name),
          unquote(inputs)
        )
        |> Sonos.Soap.request(unquote(endpoint))
        |> Sonos.Soap.response(
          unquote(action.original_name),
          unquote(action.outputs |> Macro.escape())
        )
        |> then(fn x ->
          {:soap, x}
        end)
      end

    # all "get_" functions we check the cache for data.
    cache_fetch =
      if action.name |> to_string |> String.starts_with?("get_") do
        quote do
          case Sonos.Server.cache_fetch(
                 unquote(endpoint),
                 unquote(service_module),
                 unquote(inputs),
                 unquote(action.outputs |> Macro.escape())
               ) do
            {:ok, _} = res ->
              {:cache, res}

            {:error, _} ->
              unquote(soap_fetch)
          end
        end
      else
        quote do
          Sonos.Server.cache_fetch(
            unquote(endpoint),
            unquote(service_module),
            %{},
            []
          )

          unquote(soap_fetch)
        end
      end

    output_value =
      quote do
        unquote(cache_fetch)
        |> then(fn
          {via, {:ok, resp}} ->
            {:ok, Sonos.Api.Response.new(unquote(action.name), resp.outputs, unquote(action.outputs |> Macro.escape()), via: via)}

          {_via, err} ->
            err
        end)
      end

    params = [endpoint | action.inputs |> Enum.map(fn x -> x.name |> Macro.var(nil) end)]

    validation = validate(action.inputs, output_value)

    description = function_docs["description"] || nil
    remarks = function_docs["remarks"] || nil

    sample = function_docs["sample"] || nil
    params_docs = function_docs["params"] || nil

    inputs =
      action.inputs
      |> Enum.map(fn x ->
        original_name = x.original_name |> to_string()

        description = params_docs && params_docs[original_name]

        description =
          case sample && sample[original_name] do
            nil ->
              description

            sample when not is_binary(sample) or sample != "" ->
              description <> " (eg #{sample})"

            _ ->
              description
          end

        if description do
          {x.name, description}
        end
      end)
      |> Enum.filter(& &1)

    outputs =
      action.outputs
      |> Enum.map(fn x ->
        original_name = x.original_name |> to_string()
        description = params_docs && params_docs[original_name]
        {x.name, description}
      end)
      |> Enum.filter(& &1)

    input_docs =
      quote do
        unquote("""
        ## Parameters

        * `endpoint`: The endpoint of the device to call (eg `http://192.168.1.96:1400`)
        #{inputs |> Enum.map(fn {name, description} -> "* `#{name}`: #{description}\n" end) |> Enum.join()}
        """)
      end

    output_docs =
      quote do
        unquote("""
        ## Outputs

        #{outputs |> Enum.map(fn {name, description} -> "* `#{name}`: #{description}\n" end) |> Enum.join()}
        """)
      end

    # TODO we can do typespecs
    quote do
      @doc """
      #{unquote(description)}

      #{unquote(input_docs)}

      #{unquote(output_docs)}

      #{unquote(remarks)}
      """
      def unquote(action.name)(unquote_splicing(params)) when is_binary(unquote(endpoint)) do
        unquote(validation)
      end
    end
  end
end
