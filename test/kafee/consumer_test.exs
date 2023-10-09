defmodule Kafee.ConsumerTest do
  use Kafee.BrodCase, async: false

  require Record

  alias Kafee.Consumer

  # Use Record module to extract fields of the Span record from the opentelemetry dependency.
  @span_fields Record.extract(:span, from: "deps/opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:span, @span_fields)

  setup do
    spy(Kafee.Consumer)
    on_exit(fn -> restore(Kafee.Consumer) end)

    spy(Datadog.DataStreams.Integrations.Kafka)
    on_exit(fn -> restore(Datadog.DataStreams.Integrations.Kafka) end)
  end

  describe "start_link/2" do
    test "validates options" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Consumer.start_link(__MODULE__,
                 backend: 101
               )
    end

    test "starts the backend process tree" do
      topic = Kafee.KafkaApi.generate_topic()
      :ok = Kafee.KafkaApi.create_topic(topic)

      assert {:ok, pid} =
               Consumer.start_link(MyConsumer,
                 backend: {Kafee.Consumer.BroadwayBackend, []},
                 host: Kafee.KafkaApi.host(),
                 port: Kafee.KafkaApi.port(),
                 consumer_group_id: Kafee.KafkaApi.generate_consumer_group_id(),
                 topic: topic
               )

      assert is_pid(pid)
    end
  end

  describe "push_messages/2" do
    test "it pushes each message" do
      assert :ok = Consumer.push_messages(MyConsumer, Kafee.BrodApi.generate_consumer_message_list(3))
      assert_called Kafee.Consumer.push_message(MyConsumer, _message), 3
    end
  end

  describe "push_message/2" do
    test "catches any error raised and returns :ok" do
      message = Kafee.BrodApi.generate_consumer_message()
      error = %RuntimeError{message: "testing error handling"}

      patch(MyConsumer, :handle_message, fn _ -> raise error end)

      assert :ok = Consumer.push_message(MyConsumer, message)
      # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
      assert_called MyConsumer.handle_failure(^error, ^message)
    end

    test "calls Datadog.DataStreams.Integration.Kafka.trace_consume/2" do
      message = Kafee.BrodApi.generate_consumer_message(consumer_group: "my-consumer-group")

      assert :ok = Consumer.push_message(MyConsumer, message)
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

      assert :ok = Consumer.push_message(MyConsumer, message)
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

      assert :ok = Consumer.push_message(MyConsumer, message)

      otel_attributes =
        :otel_attributes.new(
          [
            "messaging.system": "kafka",
            "messaging.operation": "process",
            "messaging.source.name": "testing test topic",
            "messaging.kafka.message.key": "key test",
            "messaging.kafka.consumer.group": "testing push message",
            "messaging.kafka.source.partition": 2,
            "messaging.kafka.message.offset": 15
          ],
          128,
          :infinity
        )

      assert_receive {:span,
                      span(
                        name: "testing test topic consume",
                        attributes: ^otel_attributes
                      )}
    end

    test "extracts the correlation id into logger" do
      Logger.metadata([])

      message = Kafee.BrodApi.generate_consumer_message(headers: [{"kafka_correlationId", "testy mctester"}])

      assert :ok = Consumer.push_message(MyConsumer, message)

      metadata = Logger.metadata()
      assert "testy mctester" = Keyword.get(metadata, :request_id)
    end
  end
end
