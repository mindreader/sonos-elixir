defmodule Sonos.Device.Subscription do
  alias __MODULE__

  defstruct state: nil,
            subscription_id: nil,
            timeout: nil,
            max_age: nil,
            last_updated_at: nil,
            last_subscribed_at: nil,
            resubscribe_last_sent_at: nil

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
      last_updated_at: Timex.now(),

      # this is when we last subscribed or updated our subscription.
      last_subscribed_at: nil,

      # if we sent a resubscribe, this is the last time it happened, which is useful
      # to know while we are waiting for the resub response.
      resubscribe_last_sent_at: nil
    }
  end

  def merge(state, _service, vars, _opts \\ [])

  def merge(%Subscription{state: nil} = state, _service, vars, _opts) do
    %Subscription{state | state: vars, last_updated_at: Timex.now()}
  end

  def merge(%Subscription{} = state, service, vars, _opts) do
    substate =
      case service do
        # These services are broken down by instance (or queue) id,
        # for each instance may only send some vars, so we merge them
        "RenderingControl:1" ->
          vars |> Map.merge(state.state, fn _k, v1, v2 -> Map.merge(v1, v2) end)

        "Queue:1" ->
          vars |> Map.merge(state.state, fn _k, v1, v2 -> Map.merge(v1, v2) end)

        # everything else is just a simple taking the newest vars present.
        _ ->
          state.state |> Map.merge(vars)
      end

    %Subscription{state | state: substate, last_updated_at: Timex.now()}
  end

  def subscribed(%Subscription{} = state, subscription_id, max_age, %DateTime{} = dt) do
    %Subscription{
      state
      | subscription_id: subscription_id,
        max_age: max_age,
        last_subscribed_at: dt
    }
  end

  def resubscribe_sent(%Subscription{} = state, %DateTime{} = dt) do
    %Subscription{state | resubscribe_last_sent_at: dt}
  end

  def resubscribed(%Subscription{} = state, %DateTime{} = dt) do
    %Subscription{state | last_subscribed_at: dt}
  end

  def expired?(%Subscription{} = state) do
    state.last_subscribed_at &&
      state.last_subscribed_at
      |> Timex.shift(seconds: state.max_age)
      |> Timex.before?(Timex.now())
  end

  def expiring?(%Subscription{} = state) do
    half_max_age = state.max_age |> div(2)
    state.last_subscribed_at |> Timex.shift(seconds: half_max_age) |> Timex.before?(Timex.now())
  end

  @doc """
  Fetches the state variables for a given service and inputs.

  Where the variable is located within unparsed state varies based on service, so we try to look
  at inputs that were passed to the function as well as the shape of the state at that point
  and then work our way down to extract the right value for that variable.

  Ideally we would do this parsing once before storing in subscription, but then we'd have to define
  our own layout to follow and then do basically the same sort of logic, so we'd only be saving
  a little memory and cpu time, not enough to be worth the effort at this time.
  """
  def fetch_vars(inputs, outputs) do
    fn %Subscription{state: state} ->
      outputs
      |> Enum.reduce(%{}, fn x, accum ->
        main_value = state

        # many commands are prefixed by instance id in their state. If we have input an instance id
        # then use it to index into the state. Some commands take an instance id but their state
        # is not under the instance id, so we check for both possibilities
        instance_id = inputs |> Keyword.get(:InstanceID, :not_specified)

        main_value =
          if instance_id != :not_specified do
            case main_value |> Map.get(to_string(instance_id)) do
              nil -> main_value
              value -> value
            end
          else
            main_value
          end

        main_value = main_value |> Map.get(x.state_variable |> to_string())

        # similar to instance id, if we passed in a channel to this command, use it to find the
        # xml element that is specific to this channel.
        main_value =
          if inputs |> Keyword.has_key?(:Channel) && is_list(main_value) do
            main_value
            |> Enum.find(fn v -> v["-channel"] == "#{inputs[:Channel]}" end)
          else
            main_value
          end

        # if the value is a map, then it is a complex type and often times
        # we need to extract the value from it.
        main_value =
          case main_value do
            %{"-val" => val} -> val
            _ -> main_value
          end

        # turn mostly strings to int or booleans as appropriate
        main_value = Sonos.Utils.coerce_data_type(main_value, x.data_type)

        accum |> Map.put(x.name, main_value)
      end)
    end
  end
end
