defmodule Kafee.Consumer.Adapter do
  @moduledoc """
  A behaviour for changing _how_ messages are fetched from
  Kafka and processed. This is made to allow new implementations
  with a simple configuration change and little to no other code
  changes.
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias Kafee.Consumer.Message

  @doc """
  Starts the lower level library responsible for fetching Kafka messages,
  converting them to `t:Kafee.Consumer.Message.t/0` and passing them back
  to the consumer via `push_message/3`.
  """
  @callback start_link(module(), Kafee.Consumer.options()) :: Supervisor.on_start()

  @doc """
  This function is used to abstract a ton of tracing function calls
  that all `Kafee.Consumer.Adapter` modules should implement.

  ## Examples

      defmodule MyConsumerAdapter do
        @behaviour Kafee.Consumer.Adapter

        @impl Kafee.Consumer.Adapter
        def start_link(consumer, options) do
          # Start the adapter processes
        end

        def handle_message(consumer, options, raw_kafka_message) do
          kafee_message = %Kafee.Consumer.Message{
            # Set these fields from the raw kafka message
          }

          # This will wrap a bunch of the Open Telemetry and
          # DataDog trace logic and push the final message
          # to the Kafee consumer module.
          Kafee.Consumer.Adapter.push_message(consumer, options, kafee_message)
        end
      end

  """
  @spec push_message(atom(), Kafee.Consumer.options(), Message.t()) :: :ok | {:error, Exception.t()}
  def push_message(consumer, options, %Message{} = message) do
    Message.set_logger_metadata(message)

    span_name = Message.get_otel_span_name(message)
    span_attributes = Message.get_otel_span_attributes(message)

    Tracer.with_span span_name, %{kind: :consumer, attributes: span_attributes} do
      Datadog.DataStreams.Integrations.Kafka.trace_consume(message, message.consumer_group)

      Datadog.DataStreams.Integrations.Kafka.track_consume(
        message.consumer_group,
        message.topic,
        message.partition,
        message.offset
      )

      new_message_value =
        case options[:decoder] do
          nil -> message.value
          decoder when is_atom(decoder) -> decoder.decode!(message.value, [])
          {decoder, decoder_options} -> decoder.decode!(message.value, decoder_options)
        end

      message = Map.put(message, :value, new_message_value)

      :telemetry.span([:kafee, :consume], %{module: consumer}, fn ->
        result = consumer.handle_message(message)
        {result, %{}}
      end)
    end

    :ok
  rescue
    error ->
      {:error, error}
  end

  @doc """
  Pushes a batch of messages to the consumer for processing.
  
  This function handles batch processing with telemetry and tracing support.
  It will attempt to use the consumer's `handle_batch/1` callback if available,
  otherwise it falls back to processing messages individually.
  
  ## Examples
  
      defmodule MyBatchConsumerAdapter do
        @behaviour Kafee.Consumer.Adapter
        
        def handle_message_batch(consumer, options, raw_kafka_messages) do
          kafee_messages = Enum.map(raw_kafka_messages, fn raw_msg ->
            %Kafee.Consumer.Message{
              # Convert raw message to Kafee message
            }
          end)
          
          # This will handle telemetry, tracing, and decoding
          Kafee.Consumer.Adapter.push_batch(consumer, options, kafee_messages)
        end
      end
  
  """
  @spec push_batch(atom(), Kafee.Consumer.options(), [Message.t()]) :: 
    :ok | {:ok, failed_messages :: [Message.t()]} | {:error, Exception.t()}
  def push_batch(consumer, options, messages) when is_list(messages) do
    # Set logger metadata for the first message (for context)
    case messages do
      [first | _] -> Message.set_logger_metadata(first)
      [] -> :ok
    end
    
    # Build batch span name and attributes
    {span_name, span_attributes} = build_batch_span_info(messages)
    
    Tracer.with_span span_name, %{kind: :consumer, attributes: span_attributes} do
      # Track DataDog data streams for batch
      track_batch_datastreams(messages)
      
      # Decode all messages in the batch
      decoded_messages = decode_batch_messages(messages, options)
      
      # Execute telemetry span for batch processing
      :telemetry.span(
        [:kafee, :consume_batch],
        %{
          module: consumer,
          batch_size: length(decoded_messages),
          topic: get_batch_topic(decoded_messages),
          partition: get_batch_partition(decoded_messages)
        },
        fn ->
          result = process_batch(consumer, decoded_messages)
          
          # Build telemetry metadata based on result
          metadata = build_batch_telemetry_metadata(result, decoded_messages)
          
          {result, metadata}
        end
      )
    end
  rescue
    error ->
      {:error, error}
  end
  
  # Private helper functions for batch processing
  
  defp build_batch_span_info(messages) do
    case messages do
      [] -> 
        {"kafee.consume_batch", %{batch_size: 0}}
        
      [first | _] = msgs ->
        span_name = "kafee.consume_batch.#{first.topic}"
        
        # Get offset range
        offsets = Enum.map(msgs, & &1.offset)
        min_offset = Enum.min(offsets)
        max_offset = Enum.max(offsets)
        
        attributes = %{
          "messaging.system" => "kafka",
          "messaging.destination" => first.topic,
          "messaging.destination_kind" => "topic",
          "messaging.kafka.consumer_group" => first.consumer_group,
          "messaging.kafka.partition" => first.partition,
          "messaging.batch.message_count" => length(msgs),
          "messaging.kafka.offset.min" => min_offset,
          "messaging.kafka.offset.max" => max_offset
        }
        
        {span_name, attributes}
    end
  end
  
  defp track_batch_datastreams(messages) do
    # Track each message for data streams
    Enum.each(messages, fn message ->
      Datadog.DataStreams.Integrations.Kafka.trace_consume(message, message.consumer_group)
      
      Datadog.DataStreams.Integrations.Kafka.track_consume(
        message.consumer_group,
        message.topic,
        message.partition,
        message.offset
      )
    end)
  end
  
  defp decode_batch_messages(messages, options) do
    decoder_config = options[:decoder]
    
    Enum.map(messages, fn message ->
      new_value = 
        case decoder_config do
          nil -> message.value
          decoder when is_atom(decoder) -> decoder.decode!(message.value, [])
          {decoder, decoder_options} -> decoder.decode!(message.value, decoder_options)
        end
        
      Map.put(message, :value, new_value)
    end)
  end
  
  defp process_batch(consumer, messages) do
    if function_exported?(consumer, :handle_batch, 1) do
      consumer.handle_batch(messages)
    else
      # Fall back to individual processing
      process_messages_individually(consumer, messages)
    end
  end
  
  defp process_messages_individually(consumer, messages) do
    results = Enum.map(messages, fn message ->
      try do
        {message, consumer.handle_message(message)}
      rescue
        error -> {message, {:error, error}}
      end
    end)
    
    failed_messages = 
      results
      |> Enum.filter(fn
        {_msg, :ok} -> false
        {_msg, {:error, _}} -> true
        _ -> true
      end)
      |> Enum.map(fn {msg, _} -> msg end)
    
    if failed_messages == [] do
      :ok
    else
      {:ok, failed_messages}
    end
  end
  
  defp build_batch_telemetry_metadata(result, messages) do
    base_metadata = %{
      batch_size: length(messages)
    }
    
    case result do
      :ok -> 
        Map.put(base_metadata, :failed_count, 0)
        
      {:ok, failed_messages} ->
        base_metadata
        |> Map.put(:failed_count, length(failed_messages))
        |> Map.put(:success_count, length(messages) - length(failed_messages))
        
      {:error, reason} ->
        base_metadata
        |> Map.put(:failed_count, length(messages))
        |> Map.put(:error, reason)
    end
  end
  
  defp get_batch_topic([]), do: nil
  defp get_batch_topic([first | _]), do: first.topic
  
  defp get_batch_partition([]), do: nil
  defp get_batch_partition([first | _]), do: first.partition
end
