defmodule Kafee.Consumer.Message do
  @moduledoc """
  A message struct for messages that have been received from Kafka.
  This is standardized data from Kafka no matter the lower level
  backend the consumer is using. Every `Kafee.Backend` implementation
  is responsible for fetching this data and convert a message to this
  struct.
  """

  @derive {Jason.Encoder, except: []}

  defstruct [
    :key,
    :value,
    :topic,
    :partition,
    :offset,
    :consumer_group,
    :timestamp,
    headers: []
  ]

  @type t :: %__MODULE__{
          key: binary(),
          value: binary(),
          topic: :brod.topic(),
          partition: :brod.partition(),
          offset: integer(),
          consumer_group: binary(),
          # unix epoch in Kafka
          timestamp: DateTime.t(),
          headers: :kpro.headers()
        }
end
