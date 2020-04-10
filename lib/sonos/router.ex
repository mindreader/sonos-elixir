defmodule Sonos.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  match _ do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "OK")
  end
end
