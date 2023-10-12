defmodule Kafee.Consumer.BackendTest do
  use Kafee.BrodCase

  require Record

  alias Kafee.Consumer.Backend

  # Use Record module to extract fields of the Span record from the opentelemetry dependency.
  @span_fields Record.extract(:span, from: "deps/opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:span, @span_fields)

  @consumer_options [
    decoder: {Kafee.NilEncoderDecoder, []}
  ]

  setup do
    spy(Kafee.Consumer.Backend)
    on_exit(fn -> restore(Kafee.Consumer.Backend) end)

    spy(Datadog.DataStreams.Integrations.Kafka)
    on_exit(fn -> restore(Datadog.DataStreams.Integrations.Kafka) end)
  end

  describe "push_message/2" do
    test "catches any error raised and returns :ok" do
      message = Kafee.BrodApi.generate_consumer_message()
      error = %RuntimeError{message: "testing error handling"}

      patch(MyConsumer, :handle_message, fn _ -> raise error end)

      assert :ok = Backend.push_message(MyConsumer, @consumer_options, message)
      # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
      assert_called MyConsumer.handle_failure(^error, ^message)
    end

    test "calls Datadog.DataStreams.Integration.Kafka.trace_consume/2" do
      message = Kafee.BrodApi.generate_consumer_message(consumer_group: "my-consumer-group")

      assert :ok = Backend.push_message(MyConsumer, @consumer_options, message)
      # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
      assert_called Datadog.DataStreams.Integrations.Kafka.trace_consume(^message, "my-consumer-group")
    end

    test "calls Datadog.DataStreams.Integration.Kafka.track_consume/2" do
      message =
        Kafee.BrodApi.generate_consumer_message(
          consumer_group: "my-consumer-group",
          topic: "test-topic",
          partition: 2,
          offset: 4
        )

      assert :ok = Backend.push_message(MyConsumer, @consumer_options, message)
      assert_called Datadog.DataStreams.Integrations.Kafka.track_consume("my-consumer-group", "test-topic", 2, 4)
    end

    test "creates an open telemetry span" do
      :otel_simple_processor.set_exporter(:otel_exporter_pid, self())

      message =
        Kafee.BrodApi.generate_consumer_message(
          key: "key test",
          consumer_group: "testing push message",
          topic: "testing test topic",
          partition: 2,
          offset: 15
        )

      assert :ok = Backend.push_message(MyConsumer, @consumer_options, message)

      assert_receive {:span, span(name: "testing test topic process")}
    end

    test "extracts the correlation id into logger" do
      Logger.metadata([])

      message = Kafee.BrodApi.generate_consumer_message(headers: [{"kafka_correlationId", "testy mctester"}])

      assert :ok = Backend.push_message(MyConsumer, @consumer_options, message)

      metadata = Logger.metadata()
      assert "testy mctester" = Keyword.get(metadata, :request_id)
    end
  end
end
