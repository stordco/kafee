defmodule Kafee.Producer.SyncAdapterTest do
  use Kafee.KafkaCase

  alias Kafee.Producer.Message

  defmodule MyProducer do
    use Kafee.Producer,
      adapter: Kafee.Producer.SyncAdapter,
      encoder: Kafee.JasonEncoderDecoder,
      partition_fun: :random
  end

  setup do
    spy(:brod)
    on_exit(fn -> restore(:brod) end)

    spy(Datadog.DataStreams.Integrations.Kafka)
    on_exit(fn -> restore(Datadog.DataStreams.Integrations.Kafka) end)

    :ok
  end

  setup %{topic: topic} do
    start_supervised!(
      {MyProducer,
       [
         host: BrodApi.host(),
         port: BrodApi.port(),
         topic: topic
       ]}
    )

    :ok
  end

  describe "partitions/2" do
    test "returns a list of valid partitions" do
      options = :ets.lookup_element(:kafee_config, MyProducer, 2)
      partitions = Kafee.Producer.SyncAdapter.partitions(MyProducer, options)
      assert [0] = partitions
    end
  end

  describe "produce/2" do
    test "sends messages via :brod.produce_sync_offset/5", %{topic: topic} do
      messages = BrodApi.generate_producer_message_list(topic, 2)

      assert :ok = MyProducer.produce(messages)

      # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
      assert_called(:brod.produce_sync_offset(MyProducer.BrodClient, ^topic, 0, :undefined, _message), 2)
    end

    test "returns errors from brod" do
      fake_topic = Kafee.KafkaApi.generate_topic()
      message = %Message{topic: fake_topic, partition: 0, key: "key", value: %{key: "value"}}

      assert {:error, :unknown_topic_or_partition} = MyProducer.produce(message)

      # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
      assert_called(:brod.produce_sync_offset(MyProducer.BrodClient, ^fake_topic, 0, :undefined, [%{
        key: "key",
        value: ~s({"key":"value"}),
        headers: _headers
      }]))
    end

    test "ran the message normalization pipeline", %{topic: topic} do
      spy(Message)

      message = BrodApi.generate_producer_message(topic)
      assert :ok = MyProducer.produce(message)

      # credo:disable-for-lines:5 Credo.Check.Readability.NestedFunctionCalls
      assert_called_once(Message.set_module_values(^message, MyProducer, _options))
      assert_called_once(Message.encode(^message, MyProducer, _options))
      assert_called_once(Message.partition(_message, MyProducer, _options))
      assert_called_once(Message.set_request_id_from_logger(_message))
      assert_called_once(Message.validate!(_message))
    end

    test "calls Data Streams track_produce/3 with current produce offset", %{topic: topic} do
      # We send the first message to ensure the offset gets set to something not 0. This
      # isn't strictly required, but it's nice to test that the offset number isn't just
      # being ignored or unset.
      first_message = BrodApi.generate_producer_message(topic)
      assert :ok = MyProducer.produce(first_message)

      # Then we finally send the actual messages
      more_messages = BrodApi.generate_producer_message_list(topic, 20)
      assert :ok = MyProducer.produce(more_messages)

      # Now we can assert that the actual call was made and that the offset was not 0
      # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
      assert_called(Datadog.DataStreams.Integrations.Kafka.track_produce(^topic, 0, offset))
      assert offset >= 1
    end
  end
end
