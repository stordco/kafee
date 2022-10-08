defmodule Kafee.Producer.Message do
  @moduledoc """
  A message struct for sending to Kafka.
  """

  defstruct [:key, :value, :topic, :partition, :partition_fun]

  @type t :: %__MODULE__{
          key: binary(),
          value: binary(),
          topic: :brod.topic(),
          partition: :brod.partition(),
          partition_fun: :brod.partition_fun()
        }
end
