defmodule Sonos.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  match _ do
    {:ok, body, conn} = conn |> Plug.Conn.read_body()

    body |> IO.puts
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "OK")
  end
end
