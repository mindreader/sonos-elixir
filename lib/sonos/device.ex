defmodule Sonos.Device do
  defstruct id: nil, ip: nil, location: nil, household: nil


  def new(id, ip, location, household) do
    %Sonos.Device {
      id: id,
      ip: ip,
      location: location,
      household: household,
    }
  end

  def from_headers(headers, ip) do
    house = headers["x-rincon-household"] || :unknown_household
    location = headers["location"] || :unknown_location
    usn = headers["usn"] || :unknown_location
    new(usn, ip, location, house)
  end
end
