defmodule Kafee.Producer.Message do
  @moduledoc """
  A message struct for messages that are being sent to Kafka.
  This is standardized data from Kafka no matter the lower level
  adapter the consumer is using.
  """

  alias __MODULE__

  @derive {Jason.Encoder, except: []}

  defstruct [
    :key,
    :value,
    :topic,
    :partition,
    :partition_fun,
    headers: []
  ]

  defmodule ValidationError do
    @moduledoc false
    defexception [:error_key, :kafee_message, :message]
  end

  @type t :: %Message{
          key: Kafee.key(),
          value: Kafee.value() | any(),
          topic: Kafee.topic(),
          partition: Kafee.partition(),
          partition_fun: Kafee.partition_fun(),
          headers: Kafee.headers()
        }

  @doc """
  Sets message keys that are `nil` to values from the producer
  module. This allows you to _not_ specify a topic or partition
  function in the message, but inherit it via the producer
  module options.

  ## Examples

      iex> set_module_values(%Message{}, MyProducer, [topic: "my-topic"])
      %Message{topic: "my-topic"}

      iex> set_module_values(%Message{}, MyProducer, [partition_fun: :hash])
      %Message{partition_fun: :hash}

  """
  @spec set_module_values(t(), module(), Kafee.Producer.options()) :: t()
  def set_module_values(%Message{} = message, _producer, options) do
    message
    |> replace_nil(:topic, options[:topic])
    |> replace_nil(:partition_fun, options[:partition_fun])
  end

  defp replace_nil(map, key, value) do
    if map |> Map.get(key, nil) |> is_nil(),
      do: Map.put(map, key, value),
      else: map
  end

  @doc """
  Encodes the message value with the set producer encoder decoder
  module and adds the encoder decoder module's content type to the
  message headers.

  ## Examples

      iex> encode(%Message{value: %{key: "value"}}, MyProducer, encoder: Kafee.JasonEncoderDecoder)
      %Message{value: ~s({"key":"value"}), headers: [{"kafka_contentType", "application/json"}]}

  """
  @spec encode(t(), module(), Kafee.Producer.options()) :: t()
  def encode(%Message{} = message, _producer, options) do
    case Keyword.get(options, :encoder, nil) do
      nil ->
        message

      encoder when is_atom(encoder) ->
        encoded_value = encoder.encode!(message.value, [])
        content_type = encoder.content_type()
        set_content_type(%{message | value: encoded_value}, content_type)

      {encoder, encoder_options} ->
        encoded_value = encoder.encode!(message.value, encoder_options)
        content_type = encoder.content_type()
        set_content_type(%{message | value: encoded_value}, content_type)
    end
  end

  @doc """
  If a message partition value is not set, this function will
  call the set `partition_fun` function to give the message a
  partition.

  ## Examples

      iex> partition(%Message{partition: 12}, MyProducer, [])
      %Message{partition: 12}

      iex> message = %Message{key: "key", value: "value", partition_fun: :random}
      ...> partition(message, MyProducer, [])
      %Message{key: "key", value: "value", partition: 0, partition_fun: :random}

  """
  @spec partition(t(), module(), Kafee.Producer.options()) :: t()
  def partition(%Message{partition: nil} = message, producer, opts) do
    # We override the topic because messages being consumed and technically
    # be published to dynamic topics.
    options_with_correct_topic = Keyword.put(opts, :topic, message.topic)

    valid_partitions =
      case Keyword.get(opts, :adapter, nil) do
        # If no adapter is set, then we can't partition, so we default to something.
        nil -> [0]
        adapter when is_atom(adapter) -> adapter.partitions(producer, options_with_correct_topic)
        {adapter, _adapter_opts} -> adapter.partitions(producer, options_with_correct_topic)
      end

    partition = do_partition(message, valid_partitions)
    %{message | partition: partition}
  end

  def partition(message, _producer, _opts), do: message

  defp do_partition(%Message{partition_fun: :random}, valid_partitions) do
    Enum.random(valid_partitions)
  end

  defp do_partition(%Message{key: key, partition_fun: :hash}, valid_partitions) do
    hash_value = rem(:erlang.phash2(key), length(valid_partitions))
    Enum.at(valid_partitions, hash_value)
  end

  defp do_partition(%Message{key: key, value: value, topic: topic, partition_fun: fun}, valid_partitions)
       when is_function(fun, 4) do
    fun.(topic, valid_partitions, key, value)
  end

  @doc """
  Sets the "kafka_correlationId" header in the message to the current
  Elixir request id from `Logger` metadata. The header key name itself
  comes from the official Java Spring library correlation id header.
  This matches logic in the consumer to automatic populate the `Logger`
  metadata from a message.

  ## Examples

      iex> set_request_id(%Message{}, "testing")
      %Kafee.Producer.Message{
        headers: [{"kafka_correlationId", "testing"}]
      }

  """
  @spec set_request_id(t(), String.t()) :: t()
  def set_request_id(%Message{} = message, request_id) do
    new_headers =
      message.headers
      |> Enum.reject(fn {k, _v} -> k == "kafka_correlationId" end)
      |> Enum.concat([{"kafka_correlationId", request_id}])

    %{message | headers: new_headers}
  end

  @doc """
  Sets the message request id from the current `Logger` metadata.
  If the current `Logger` metadata has no `request_id` key, it
  does nothing. See `set_request_id/2` for more information.

  ## Examples

      iex> Logger.metadata(request_id: "testing")
      ...> set_request_id_from_logger(%Message{})
      %Kafee.Producer.Message{
        headers: [{"kafka_correlationId", "testing"}]
      }

  """
  @spec set_request_id_from_logger(t()) :: t()
  def set_request_id_from_logger(%Message{} = message) do
    case Keyword.get(Logger.metadata(), :request_id, nil) do
      request_id when is_binary(request_id) -> set_request_id(message, request_id)
      _ -> message
    end
  end

  @doc """
  Sets the `kafka_contentType` header in a message.
  """
  @spec set_content_type(t(), binary()) :: t()
  def set_content_type(%Message{} = message, content_type) do
    new_headers =
      message.headers
      |> Enum.reject(fn {k, _v} -> k == "kafka_contentType" end)
      |> Enum.concat([{"kafka_contentType", content_type}])

    %{message | headers: new_headers}
  end

  @doc """
  Checks if the given message has a header with the given key.
  """
  @spec has_header?(t(), binary()) :: boolean()
  def has_header?(%Message{} = message, key) do
    Enum.any?(message.headers, fn {k, _v} -> k == key end)
  end

  @doc """
  Validates that the requires fields in a message are set. Raises
  `Kafee.Producer.Message.ValidationError` on a missing or incorrect field.
  """
  @spec validate!(t()) :: t()
  def validate!(%Message{topic: nil} = message),
    do:
      raise(ValidationError,
        error_key: :topic,
        kafee_message: message,
        message: "Topic is missing from message"
      )

  def validate!(%Message{topic: ""} = message),
    do:
      raise(ValidationError,
        error_key: :topic,
        kafee_message: message,
        message: "Topic is empty in message"
      )

  def validate!(%Message{partition: nil} = message),
    do:
      raise(ValidationError,
        error_key: :partition,
        kafee_message: message,
        message: "Partition is missing from message"
      )

  def validate!(%Message{} = message) do
    for {key, value} <- message.headers do
      if not (is_binary(key) and is_binary(value)) do
        raise(ValidationError,
          error_key: :headers,
          kafee_message: message,
          message: "Header key or value is not a binary value"
        )
      end
    end

    message
  end

  @doc """
  Returns the Open Telemetry trace span for producing this message.
  This follows the [OTEL 1.25.0 trace spec for messaging systems][doc].

  [doc]: https://opentelemetry.io/docs/specs/otel/trace/semantic_conventions/messaging/

  ## Examples

      iex> get_otel_span_name(%Message{
      ...>  topic: "test topic"
      ...> })
      "test topic publish"

      iex> get_otel_span_name(%Message{})
      "(anonymous) publish"

  """
  @spec get_otel_span_name(t()) :: String.t()
  def get_otel_span_name(%Message{} = message) do
    prefix = if is_nil(message.topic), do: "(anonymous)", else: message.topic
    prefix <> " publish"
  end

  @doc """
  Returns the Open Telemetry trace attributes for producing this message.
  This follows the [OTEL 1.25.0 trace spec for messaging systems][doc].
  Note that this function should be called after any encoding or decoding
  of the message value to binary so we can get an accurate byte size of
  the message value.

  [doc]: https://opentelemetry.io/docs/specs/otel/trace/semantic_conventions/messaging/

  ## Examples

      iex> get_otel_span_attributes([%Message{
      ...>   key: "test-message",
      ...>   value: "message value",
      ...>   topic: "test-topic",
      ...>   partition: 1,
      ...> }])
      %{
        "messaging.system": "kafka",
        "messaging.destination.name": "test-topic",
        "messaging.batch.message_count": 1,
        "messaging.kafka.partition": 1
      }

      iex> get_otel_span_attributes(%Message{
      ...>   key: "test-message",
      ...>   value: "message value",
      ...>   topic: "test-topic",
      ...>   partition: 1,
      ...> })
      %{
        "messaging.system": "kafka",
        "messaging.destination.name": "test-topic",
        "messaging.message.payload_size_bytes": 13,
        "messaging.kafka.message.key": "test-message",
        "messaging.kafka.partition": 1
      }

      iex> get_otel_span_attributes(%Message{
      ...>   value: "message value"
      ...> })
      %{
        "messaging.system": "kafka",
        "messaging.message.payload_size_bytes": 13
      }

  """
  @spec get_otel_span_attributes(t() | [t()]) :: map()
  def get_otel_span_attributes([message | _] = messages) when is_list(messages) do
    message
    |> get_otel_span_attributes()
    |> Map.put(:"messaging.batch.message_count", length(messages))
    |> Map.drop([
      :"messaging.message.payload_size_bytes",
      :"messaging.kafka.message.key"
    ])
  end

  def get_otel_span_attributes(%Message{value: value} = message) when is_binary(value) do
    [
      {:"messaging.system", "kafka"},
      {:"messaging.destination.name", message.topic},
      {:"messaging.message.payload_size_bytes", byte_size(message.value)},
      {:"messaging.kafka.message.key", message.key},
      {:"messaging.kafka.partition", message.partition}
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  def get_otel_span_attributes(%Message{} = message) do
    inspected_message = inspect(message)

    raise RuntimeError,
      message: """
      Unable to generate OpenTelemetry span attributes for Kafee producer
      message because the value is not a bitstring. This usually indicates
      that the message has not yet been encoded into a binary value
      before calling this function.

      Message:
      #{inspected_message}
      """
  end
end
