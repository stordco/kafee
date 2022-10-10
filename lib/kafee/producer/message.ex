defmodule Kafee.Producer.Message do
  @moduledoc """
  A message struct for sending to Kafka.
  """

  defstruct [:key, :value, :topic, :partition, :partition_fun, headers: []]

  @type t :: %__MODULE__{
          key: binary(),
          value: binary(),
          topic: :brod.topic() | nil,
          partition: :brod.partition() | nil,
          partition_fun: :brod.partitioner() | nil,
          headers: :kpro.headers() | nil
        }
end
