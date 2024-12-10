defmodule SonosWeb.Audio do
  use SonosWeb, :controller

  def fetch(conn, _params) do
    conn
    |> put_resp_content_type("audio/mpeg")
    |> send_file(200, "/home/toad/bit/01-fpm-sunshine.mp3")
  end
end
