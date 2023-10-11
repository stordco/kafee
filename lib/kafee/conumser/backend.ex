defmodule Kafee.Consumer.Backend do
  @moduledoc """
  A drop in interface for changing _how_ messages are fetched from
  Kafka and processed. This is made to allow new implementations
  with a simple configuration change and little to no other code
  changes.
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias Kafee.Consumer.Message

  @doc """
  Starts the lower level library responsible for fetching Kafka messages,
  converting them to `t:Kafee.Consumer.Message.t/0` and passing them back
  to the consumer via `Kafee.Consumer.push_message/2`.
  """
  @callback start_link(module(), Kafee.Consumer.options()) :: Supervisor.on_start()

  @doc """
  This function is used to abstract a ton of tracing function calls
  that all `Kafee.Consumer.Backend` modules should implement.

  ## Examples

      defmodule MyConsumerBackend do
        @behaviour Kafee.Consumer.Backend

        @impl Kafee.Consumer.Backend
        def start_link(module, options) do
          # Start the backend processes
        end

        def handle_message(module, module_options, raw_kafka_message) do
          kafee_message = %Kafee.Consumer.Message{
            # Set these fields from the raw kafka message
          }

          # This will wrap a bunch of the Open Telemetry and
          # DataDog trace logic and push the final message
          # to the Kafee consumer module.
          Kafee.Consumer.Backend.push_message(module, module_options, kafee_message)
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

      {decoder, decoder_options} = options[:decoder]
      new_message_value = decoder.decode!(message.value, decoder_options)

      message
      |> Map.put(:value, new_message_value)
      |> module.handle_message()
    end

    :ok
  rescue
    error ->
      module.handle_failure(error, message)
      :ok
  end
end
