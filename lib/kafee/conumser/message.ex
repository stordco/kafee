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
          value: any(),
          topic: binary(),
          partition: -2_147_483_648..2_147_483_647,
          offset: integer(),
          consumer_group: binary(),
          timestamp: DateTime.t(),
          headers: [{binary(), binary()}]
        }

  @doc """
  Returns the value of the "kafka_correlationId" header. This holds the Elixir
  request id from the producer. The header key name itself comes from the official
  Java Spring library correlation id header.

  ## Examples

      iex> get_request_id(%Kafee.Consumer.Message{
      ...>   headers: [{"kafka_correlationId", "testing"}]
      ...> })
      "testing"

      iex> get_request_id(%Kafee.Consumer.Message{})
      nil

  """
  @spec get_request_id(t()) :: String.t() | nil
  def get_request_id(message) do
    case Enum.find(message.headers, fn {k, _v} -> k === "kafka_correlationId" end) do
      nil -> nil
      {"kafka_correlationId", request_id} -> request_id
    end
  end

  @doc """
  Returns the Open Telemetry trace span for consuming this message.
  This follows the [OTEL 1.25.0 trace spec for messaging systems][doc].

  [doc]: https://opentelemetry.io/docs/specs/otel/trace/semantic_conventions/messaging/

  ## Examples

      iex> get_otel_span_name(%Kafee.Consumer.Message{
      ...>  topic: "test topic"
      ...> })
      "test topic process"

      iex> get_otel_span_name(%Kafee.Consumer.Message{})
      "(anonymous) process"

  """
  @spec get_otel_span_name(t()) :: String.t()
  def get_otel_span_name(message) do
    prefix = if is_nil(message.topic), do: "(anonymous)", else: message.topic
    prefix <> " process"
  end

  @doc """
  Returns the Open Telemetry trace attributes for consuming this message.
  This follows the [OTEL 1.25.0 trace spec for messaging systems][doc].
  Note that this function should be called before any encoding or decoding
  of the message value from binary.

  [doc]: https://opentelemetry.io/docs/specs/otel/trace/semantic_conventions/messaging/

  ## Examples

      iex> get_otel_span_attributes(%Kafee.Consumer.Message{
      ...>   key: "test-message",
      ...>   value: "message value",
      ...>   topic: "test-topic",
      ...>   partition: 1,
      ...>   offset: 0,
      ...>   consumer_group: "my-consumer-group"
      ...> })
      %{
        "messaging.system": "kafka",
        "messaging.source.name": "test-topic",
        "messaging.operation": "process",
        "messaging.message.payload_size_bytes": 13,
        "messaging.kafka.message.key": "test-message",
        "messaging.kafka.consumer.group": "my-consumer-group",
        "messaging.kafka.partition": 1,
        "messaging.kafka.message.offset": 0
      }

      iex> get_otel_span_attributes(%Kafee.Consumer.Message{
      ...>   value: "message value"
      ...> })
      %{
        "messaging.system": "kafka",
        "messaging.message.payload_size_bytes": 13,
        "messaging.operation": "process",
      }

  """
  @spec get_otel_span_attributes(t()) :: map()
  def get_otel_span_attributes(%Kafee.Consumer.Message{value: value} = message) when is_binary(value) do
    [
      {:"messaging.system", "kafka"},
      {:"messaging.source.name", message.topic},
      {:"messaging.operation", "process"},
      {:"messaging.message.conversation_id", get_request_id(message)},
      {:"messaging.message.payload_size_bytes", byte_size(message.value)},
      {:"messaging.kafka.message.key", message.key},
      {:"messaging.kafka.consumer.group", message.consumer_group},
      {:"messaging.kafka.partition", message.partition},
      {:"messaging.kafka.message.offset", message.offset}
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  def get_otel_span_attributes(%Kafee.Consumer.Message{} = message) do
    inspected_message = inspect(message)

    raise RuntimeError,
      message: """
      Unable to generate OpenTelemetry span attributes for Kafee consumer
      message because the value is not a bitstring. This usually indicates
      that the message has been decoded into a native Elixir data value
      before calling this function.

      Message:
      #{inspected_message}
      """
  end

  @doc false
  @spec set_logger_request_id(t()) :: no_return()
  def set_logger_request_id(message) do
    if request_id = get_request_id(message) do
      Logger.metadata(request_id: request_id)
    else
      Logger.metadata(request_id: nil)
    end
  end
end
