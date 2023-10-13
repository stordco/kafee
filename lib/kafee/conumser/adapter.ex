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
        def start_link(module, options) do
          # Start the adapter processes
        end

        def handle_message(module, module_options, raw_kafka_message) do
          kafee_message = %Kafee.Consumer.Message{
            # Set these fields from the raw kafka message
          }

          # This will wrap a bunch of the Open Telemetry and
          # DataDog trace logic and push the final message
          # to the Kafee consumer module.
          Kafee.Consumer.Adapter.push_message(module, module_options, kafee_message)
        end
      end

  """
  @spec push_message(atom(), Kafee.Consumer.options(), Message.t()) :: :ok
  def push_message(module, options, %Message{} = message) do
    Message.set_logger_request_id(message)

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

      :telemetry.span([:kafee, :consume], %{module: module}, fn ->
        result = module.handle_message(message)
        {result, %{}}
      end)
    end

    :ok
  rescue
    error ->
      module.handle_failure(error, message)
      :ok
  end
end
