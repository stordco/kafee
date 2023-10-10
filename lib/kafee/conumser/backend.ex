defmodule Kafee.Consumer.Backend do
  @moduledoc """
  A drop in interface for changing _how_ messages are fetched from
  Kafka and processed. This is made to allow new implementations
  with a simple configuration change and little to no other code
  changes.
  """

  @doc """
  Starts the lower level library responsible for fetching Kafka messages,
  converting them to `t:Kafee.Consumer.Message.t/0` and passing them back
  to the consumer via `Kafee.Consumer.push_message/2`.
  """
  @callback start_link(module(), Kafee.Consumer.options()) :: Supervisor.on_start()
end
