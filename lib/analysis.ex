defmodule Analysis do
  @moduledoc """
  This module is for analyzing sonos network and devices. They return xml and it is a bit
  of a hassle to deal with, so we just convert it to json since we only have to do it once during
  development so we can be sure we have good data to work with from then on.
  """

  require Logger

  # xml to json doesn't always return lists because it doesn't know if there will be more than
  # one attribute of a type in xml tag, so we coerce things we know are meant to be lists.
  defp coerce_to_list(x) do
    case x do
      nil -> []
      x when is_list(x) -> x
      _ -> [x]
    end
  end

  # url eg. "http://192.168.0.48:1400/xml/ajmja/L3F.xml"
  def query_device(url) when is_binary(url) do
    Logger.info("querying device #{url}")

    uri = url |> URI.parse()
    root = %URI{uri | path: nil} |> URI.to_string()

    url
    |> HTTPoison.get()
    |> case do
      {:error, _} = err ->
        Logger.error("error querying device #{url}: #{inspect(err)}")
        err

      {:ok, %HTTPoison.Response{} = res} ->
        root_device = res.body |> XmlToMap.naive_map() |> get_in(["root", "device"])
        Logger.info("Device: #{root_device["friendlyName"]}")

        servicef = fn service ->
          %{
            type: service["serviceType"],
            scpd_url: service["SCPDURL"],
            control_url: service["controlURL"],
            events_url: service["eventSubURL"]
          }
        end

        devicef = fn device ->
          %{
            name: device["modelName"],
            type: device["deviceType"],
            services: device["serviceList"]["service"] |> coerce_to_list() |> Enum.map(servicef)
          }
        end

        sub_devices = root_device["deviceList"]["device"] |> coerce_to_list() |> Enum.map(devicef)
        root_device = devicef.(root_device)

        [root_device | sub_devices]
        |> Enum.map(fn device ->
          services =
            device.services
            |> Enum.map(fn service ->
              scpd = "#{root}#{service.scpd_url}" |> query_service()
              service |> Map.put(:scpd, scpd)
            end)

          device |> Map.put(:services, services)
        end)
    end
  end

  # url eg. "http://192.168.0.48:1400/xml/ajmja/L3F.xml"
  def query_service(url) when is_binary(url) do
    Logger.info("querying service #{url}")

    url
    |> HTTPoison.get()
    |> case do
      {:error, _} = err ->
        Logger.error("error querying service #{url}: #{inspect(err)}")
        err

      {:ok, %HTTPoison.Response{} = res} ->
        argumentf = fn argument ->
          %{
            name: argument["name"] |> String.to_atom(),
            state_variable: argument["relatedStateVariable"] |> String.to_atom()
          }
        end

        statef = fn state ->
          %{
            name: state |> get_in(["#content", "name"]) |> String.to_atom(),
            data_type: state |> get_in(["#content", "dataType"]) |> String.to_atom(),
            send_events: state["-sendEvents"] |> then(&(&1 == "yes"))
          }
        end

        actionf = fn action ->
          arguments = action["argumentList"]["argument"] |> coerce_to_list()

          inputs =
            arguments
            |> coerce_to_list()
            |> Enum.filter(fn arg -> arg["direction"] == "in" end)
            |> Enum.map(argumentf)

          outputs =
            arguments
            |> coerce_to_list()
            |> Enum.filter(fn arg -> arg["direction"] == "out" end)
            |> Enum.map(argumentf)

          %{
            name: action["name"] |> String.to_atom(),
            inputs: inputs,
            outputs: outputs
          }
        end

        scpd = res.body |> XmlToMap.naive_map() |> Map.get("scpd")

        state_variables =
          scpd
          |> get_in(["serviceStateTable", "stateVariable"])
          |> coerce_to_list()
          |> Enum.map(statef)
          |> Enum.group_by(& &1.name)

        actionList = scpd["actionList"]["action"] |> coerce_to_list() |> Enum.map(actionf)

        %{
          actions: actionList,
          state_variables: state_variables
        }
    end
  end
end
