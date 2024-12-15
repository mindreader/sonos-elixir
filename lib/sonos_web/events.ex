defmodule SonosWeb.Events do
  use SonosWeb, :controller

  def webhook(conn, %{"usn" => usn, "service" => service}) do

    {:ok, body, conn} = conn |> Plug.Conn.read_body()

    vars = body
    |> XmlToMap.naive_map()
    |> Map.get("e:propertyset")
    |> Map.get("e:property")
    |> Sonos.Utils.coerce_to_list()
    |> Enum.map(fn var ->
      var |> Enum.to_list() |> hd
    end)
    |> Map.new()

#    case vars["LastChange"] do
#      nil ->
#
#        res = vars |> Jason.encode!(pretty: true)
#        File.write!("events-#{service}.json", res)
#      bs when is_binary(bs) ->
#        res = bs |> XmlToMap.naive_map() |> Jason.encode!(pretty: true)
#        File.write!("events-#{service}.json", res)
#    end

    Sonos.Server.update_device_state(usn, service, vars)

    json = %{success: true} |> Jason.encode!()

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, json)
  end
end
