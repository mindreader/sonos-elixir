defmodule Sonos.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  match "/audio/:filename" do
    file = "/home/toad/music/game/Switch vs Evil.mp3"

    conn |> put_resp_content_type("audio/mpeg") |> send_file(200, file)
  end

  match _ do
    {:ok, body, conn} = conn |> Plug.Conn.read_body()

    body |> IO.puts
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "OK")
  end
end
