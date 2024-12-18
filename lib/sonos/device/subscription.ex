defmodule Sonos.Device.Subscription do
  alias __MODULE__
  defstruct state: nil, subscription_id: nil, timeout: nil, max_age: nil, last_updated_at: nil

  def new(opts \\ []) do
    timeout = opts[:timeout] || 60 * 5

    %Subscription{
      # Map (service_key -> Map (var_name -> value))
      # Sometimes we have to preprocess the state to make it easier to use, other times it is
      # just a raw dump of what the server sent us.
      state: nil,

      # we request this timeout on subscribe/resubscribe soap calls.
      timeout: timeout,

      # both of these are null until the original subscription request returns.
      # this is how long it is willing to persist a subscription
      max_age: nil,
      subscription_id: nil,

      # this is the last time we saw a message from them for this device.
      last_updated_at: Timex.now()
    }
  end

  def merge(state, _service, vars, _opts \\ [])

  def merge(%Subscription{state: nil} = state, _service, vars, _opts) do
    %Subscription{state | state: vars, last_updated_at: Timex.now()}
  end

  def merge(%Subscription{} = state, service, vars, _opts) do
    substate =
      case service do
        # RenderingControl:1 is broken down by instance id, for each instance merge only changed vars
        "RenderingControl:1" ->
          vars
          |> Enum.map(fn {instance_id, new_vars} ->
            merged_vars = state.state |> Map.get(instance_id) |> Map.merge(new_vars)
            {instance_id, merged_vars}
          end)
          |> Map.new()

        # everything else is just a simple taking the newest vars present.
        _ ->
          state.state |> Map.merge(vars)
      end

    %Subscription{state | state: substate, last_updated_at: Timex.now()}
  end

  def resubscribed(%Subscription{} = state, %DateTime{} = dt) do
    %Subscription{state | last_updated_at: dt}
  end

  def expiring?(%Subscription{} = state) do
    half_max_age = state.max_age |> div(2)
    state.last_updated_at |> Timex.shift(seconds: half_max_age) |> Timex.before?(Timex.now())
  end

  def var_replacements(%Subscription{} = state, service, inputs, missing_vars) do
    case service.service_type() do
      "urn:schemas-upnp-org:service:RenderingControl:1" ->
        alternative_vars = %{
          "CurrentVolume" => fn state ->
            state[inputs[:InstanceID]]["Volume"]["#{inputs[:Channel]}"]
          end,
          "CurrentMute" => fn state ->
            state[inputs[:InstanceID]]["Mute"]["#{inputs[:Channel]}"]
          end,
          "CurrentLoudness" => fn state ->
            state[inputs[:InstanceID]]["Loudness"]["#{inputs[:Channel]}"]
          end,
          "CurrentValue" => fn state ->
            state[inputs[:InstanceID]]["#{inputs[:EQType]}"]
          end
        }

        res =
          missing_vars
          |> Enum.reduce(%{}, fn var, accum ->
            case alternative_vars |> Map.get(var) do
              nil ->
                accum

              f ->
                inputs |> IO.inspect(label: "inputs")
                accum |> Map.put(var, f.(state.state))
            end
          end)

        if res |> Enum.count() == missing_vars |> Enum.count() do
          {:ok, res}
        else
          still_missing_vars = missing_vars |> Enum.reject(fn v -> res |> Map.has_key?(v) end)
          {:error, {:still_missing_vars, still_missing_vars}}
        end

      "urn:schemas-upnp-org:service:GroupRenderingControl:1" ->
        alternative_vars = %{
          "CurrentVolume" => "GroupVolume",
          "CurrentMute" => "GroupMute"
        }

        res =
          missing_vars
          |> Enum.reduce(%{}, fn var, accum ->
            case alternative_vars[var] do
              nil ->
                accum

              alternate ->
                accum |> Map.put(var, state.state[alternate])
            end
          end)

        if res |> Enum.count() == missing_vars |> Enum.count() do
          {:ok, res}
        else
          still_missing_vars = missing_vars |> Enum.reject(fn v -> res |> Map.has_key?(v) end)
          {:error, {:still_missing_vars, still_missing_vars}}
        end

      _ ->
        {:error, {:still_missing_vars, missing_vars}}
    end
  end
end
