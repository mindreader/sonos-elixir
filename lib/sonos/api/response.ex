defmodule Sonos.Api.Response do
  alias __MODULE__

  defstruct command: nil, outputs: nil, via: nil

  def new(command, output, opts \\ []) do
    via = opts |> Keyword.get(:via, nil)
    %Response{command: command, outputs: output, via: via}
  end
end
