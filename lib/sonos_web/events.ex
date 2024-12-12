defmodule SonosWeb.Events do
  use SonosWeb, :controller

  def webhook(conn, params) do

    params |> IO.inspect(label: "params")
    {:ok, body, conn} = conn |> Plug.Conn.read_body()
    body |> IO.inspect(label: "body")

    response = %{foo: :bar}

    conn
    |> json(response)
  end
end
