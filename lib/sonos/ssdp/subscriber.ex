defmodule Sonos.SSDP.Subscriber do
  alias __MODULE__
  alias Sonos.SSDP.Device

  defstruct pid: nil,
            subject: nil

  def new(pid, subject) do
    %Subscriber{pid: pid, subject: subject}
  end

  def relevant_device(%Subscriber{} = subscriber, %Device{} = device) do
    device.usn |> String.contains?(subscriber.subject)
  end
end
