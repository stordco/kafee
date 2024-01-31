defmodule Kafee.Producer.MessageTest do
  use Kafee.KafkaCase

  import Kafee.Producer.Message

  alias Kafee.Producer.Message

  describe "doctest" do
    doctest Kafee.Producer.Message
  end

  test "it can be json encoded with Jason" do
    assert {:ok, _} = Jason.encode(%Message{key: "test", value: "test"})
  end

  describe "set_module_values/3" do
    test "sets the message topic if nil" do
      assert %Message{topic: "test-topic"} = set_module_values(%Message{}, MyProducer, topic: "test-topic")
    end

    test "does not overwrite the message topic" do
      assert %Message{topic: "my-topic"} =
               set_module_values(%Message{topic: "my-topic"}, MyProducer, topic: "invalid-topic")
    end

    test "sets the partition function if nil" do
      assert %Message{partition_fun: :hash} = set_module_values(%Message{}, MyProducer, partition_fun: :hash)
    end

    test "does not overwrite the message partition_fun" do
      assert %Message{partition_fun: :hash} =
               set_module_values(%Message{partition_fun: :hash}, MyProducer, partition_fun: :random)
    end
  end

  describe "encode/3" do
    test "does nothing if the encoder is nil" do
      message = %Message{value: "value"}
      assert ^message = encode(message, MyProducer, encoder: nil)
    end

    test "encodes a message if encoder is a module" do
      assert %Message{
               value: ~s({"key":"value"}),
               headers: [{"kafka_contentType", "application/json"}]
             } = encode(%Message{value: %{key: "value"}}, MyProducer, encoder: Kafee.JasonEncoderDecoder)
    end

    test "encodes a message if encoder is a module and options" do
      assert %Message{
               value: ~s({"key":"value"}),
               headers: [{"kafka_contentType", "application/json"}]
             } =
               encode(%Message{value: %{key: "value"}}, MyProducer, encoder: {Kafee.JasonEncoderDecoder, only: [:key]})
    end
  end

  describe "partition/3" do
    setup %{topic: topic} do
      start_supervised!(
        {MyProducer,
         [
           adapter: Kafee.Producer.SyncAdapter,
           topic: topic,
           partition_fun: :hash
         ]}
      )

      :ok
    end

    test "sets partition to 0 if no adapter is set", %{topic: topic} do
      assert %Message{partition: 0} = partition(%Message{topic: topic, partition_fun: :hash}, MyProducer, adapter: nil)
    end

    test "sets partition if adapter is a module", %{topic: topic} do
      assert %Message{partition: 0} =
               partition(%Message{topic: topic, partition_fun: :hash}, MyProducer, adapter: Kafee.Producer.SyncAdapter)
    end

    test "sets partition if adapter is a module and options", %{topic: topic} do
      assert %Message{partition: 0} =
               partition(%Message{topic: topic, partition_fun: :hash}, MyProducer,
                 adapter: {Kafee.Producer.SyncAdapter, []}
               )
    end

    test "can random partition", %{topic: topic} do
      assert %Message{partition: value} =
               partition(%Message{topic: topic, partition_fun: :random}, MyProducer,
                 adapter: Kafee.Producer.SyncAdapter
               )

      assert is_integer(value)
    end

    test "can custom partition", %{topic: topic} do
      partition_fun = fn t, p, k, v ->
        assert ^topic = t
        assert [0] = p
        assert "test" = k
        assert "test" = v
        0
      end

      message = %Message{
        key: "test",
        value: "test",
        topic: topic,
        partition_fun: partition_fun
      }

      assert %Message{partition: 0} = partition(message, MyProducer, adapter: Kafee.Producer.SyncAdapter)
    end

    test "does not partition an already partitioned message" do
      assert %Message{partition: 13} = partition(%Message{partition: 13}, MyProducer, [])
    end
  end

  describe "set_request_id/2" do
    test "adds correlation id header" do
      assert %Message{headers: [{"kafka_correlationId", "test"}]} = set_request_id(%Message{}, "test")
    end

    test "removes any already existing correlation id headers" do
      assert %Message{headers: [{"kafka_correlationId", "test"}]} =
               set_request_id(
                 %Message{
                   headers: [
                     {"kafka_correlationId", "1"},
                     {"kafka_correlationId", "2"},
                     {"kafka_correlationId", "3"},
                     {"kafka_correlationId", "4"}
                   ]
                 },
                 "test"
               )
    end
  end

  describe "set_request_id_from_logger/1" do
    test "does nothing when there is no logger request id" do
      Logger.metadata(request_id: nil)
      assert %Message{} = set_request_id_from_logger(%Message{})
    end

    test "sets request id when logger has request id" do
      Logger.metadata(request_id: "testing")
      assert %Message{headers: [{"kafka_correlationId", "testing"}]} = set_request_id_from_logger(%Message{})
    end
  end

  describe "set_content_type/2" do
    test "adds content type header" do
      assert %Message{headers: [{"kafka_contentType", "test"}]} = set_content_type(%Message{}, "test")
    end

    test "removes any already existing content type headers" do
      assert %Message{headers: [{"kafka_contentType", "test"}]} =
               set_content_type(
                 %Message{
                   headers: [
                     {"kafka_contentType", "1"},
                     {"kafka_contentType", "2"},
                     {"kafka_contentType", "3"},
                     {"kafka_contentType", "4"}
                   ]
                 },
                 "test"
               )
    end
  end

  describe "validate!/1" do
    test "raises nil topic", %{topic: topic} do
      valid_message = BrodApi.generate_producer_message(topic)

      assert_raise Message.ValidationError, "Topic is missing from message", fn ->
        validate!(%{valid_message | topic: nil})
      end
    end

    test "raises empty string topic", %{topic: topic} do
      valid_message = BrodApi.generate_producer_message(topic)

      assert_raise Message.ValidationError, "Topic is empty in message", fn ->
        validate!(%{valid_message | topic: ""})
      end
    end

    test "raises nil partition", %{topic: topic} do
      valid_message = BrodApi.generate_producer_message(topic)

      assert_raise Message.ValidationError, "Partition is missing from message", fn ->
        validate!(%{valid_message | partition: nil})
      end
    end

    test "raises on non string header key", %{topic: topic} do
      valid_message = BrodApi.generate_producer_message(topic)

      assert_raise Message.ValidationError, "Header key or value is not a binary value", fn ->
        validate!(%{valid_message | headers: [{1234, "value"}]})
      end
    end

    test "does not raise on non string header value", %{topic: topic} do
      valid_message = BrodApi.generate_producer_message(topic)

      assert validate!(%{valid_message | headers: [{"key", nil}]})
    end

    test "passes a valid message", %{topic: topic} do
      valid_message = BrodApi.generate_producer_message(topic)
      assert ^valid_message = validate!(valid_message)
    end
  end

  describe "get_otel_span_name/1" do
    test "returns otel span name" do
      message = BrodApi.generate_producer_message("testing")
      assert "testing publish" = get_otel_span_name(message)
    end

    test "returns anonymous otel span name" do
      message = BrodApi.generate_producer_message(nil)
      assert "(anonymous) publish" = get_otel_span_name(message)
    end
  end

  describe "get_otel_span_attributes/1" do
    test "returns otel span name" do
      message = BrodApi.generate_producer_message("testing")
      assert "testing publish" = get_otel_span_name(message)
    end

    test "returns anonymous otel span name" do
      message = BrodApi.generate_producer_message(nil)
      assert "(anonymous) publish" = get_otel_span_name(message)
    end
  end
end
