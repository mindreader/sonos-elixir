defmodule SonosWeb.Events do
  use SonosWeb, :controller

  def index(conn, _params) do

    response = %{foo: :bar}

    conn
    |> json(response)
  end
end
