defmodule Sonos.Utils do
  # There is no way that I can find to list routes within erlang, so this is the only way I can think
  # of to find the "default" ip address for this machine with which to advertise a route for us.
  # TODO cache this so that we aren't running it all the time.
  def our_ip do
    "ip"
    |> System.cmd(["route", "list", "default"])
    |> then(fn
      {output, 0} ->
        output |> String.split() |> Enum.at(8)

      _ ->
        nil
    end)
    |> then(fn
      nil -> {:error, :cannot_find_ip}
      ip -> {:ok, ip}
    end)
  end

  def our_port do
    Application.get_env(:sonos_elixir, SonosWeb.Endpoint)[:http][:port]
    |> then(fn
      nil -> {:error, :cannot_find_port}
      port -> {:ok, port}
    end)
  end

  def our_event_address do
    with {:ok, ip} <- our_ip(),
         {:ok, port} <- our_port() do
      {:ok, "http://#{ip}:#{port}"}
    else
      err -> err
    end
  end

  def model_detection(model) do
    case model do
      "S9" -> Sonos.Api.Playbar
      "S12" -> Sonos.Api.Play1
      "S14" -> Sonos.Api.Beam
      # I don't know what the other models are, because I don't have them.
      _ -> nil
    end
  end

  def max_age_parse(headers) do
    headers["cache-control"]
    |> then(fn
      nil -> "max-age=3600"
      str -> str
    end)
    |> String.split("=")
    |> Enum.map(&String.trim/1)
    |> List.last()
    |> case do
      # default to 1 hour if not specified
      nil ->
        3600

      "" ->
        3600

      max_age ->
        max_age
        |> Integer.parse()
        |> then(fn
          {num, _} -> num
          _ -> 3600
        end)
    end
  end
end
