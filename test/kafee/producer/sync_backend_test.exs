defmodule Kafee.Producer.SyncBackendTest do
  use Kafee.KafkaCase

  alias Kafee.Producer.{Config, SyncBackend}

  setup do
    spy(:brod)
    on_exit(fn -> restore(:brod) end)

    spy(Datadog.DataStreams.Integrations.Kafka)
    on_exit(fn -> restore(Datadog.DataStreams.Integrations.Kafka) end)

    :ok
  end

  setup %{brod_client_id: brod_client_id, topic: topic} do
    config = Config.new(brod_client_id: brod_client_id, topic: topic, partition: 0)
    {:ok, %{config: config}}
  end

  describe "produce/2" do
    test "sends messages via :brod.produce_sync/5", %{config: config, topic: topic} do
      messages = [
        %Kafee.Producer.Message{topic: topic, partition: 0, key: "key", value: "value"},
        %Kafee.Producer.Message{topic: topic, partition: 0, key: "key", value: "value"}
      ]

      assert :ok = SyncBackend.produce(config, messages)
      assert_called(:brod.produce_sync_offset(_brod_client_id, _topic, _partition, _key, _message), 2)
    end

    test "returns errors from brod", %{config: config} do
      message = %Kafee.Producer.Message{topic: "", partition: 0, key: "key", value: "value"}

      assert {:error, :unknown_topic_or_partition} = SyncBackend.produce(config, [message])
      assert_called(:brod.produce_sync_offset(_brod_client_id, _topic, _partition, _key, _message), 1)
    end
  end

  describe "Datadog.DataStreams.Integrations.Kafka" do
    test "calls track_produce/3 with current produce offset", %{config: config, topic: topic} do
      # We send the first message to ensure the offset gets set to something not 0. This
      # isn't strictly required, but it's nice to test that the offset number isn't just
      # being ignored or unset.
      first_message = BrodApi.generate_producer_message(topic)
      assert :ok = SyncBackend.produce(config, [first_message])

      # Then we finally send the actual messages
      more_messages = BrodApi.generate_producer_message_list(topic, 20)
      assert :ok = SyncBackend.produce(config, more_messages)

      # Now we can assert that the actual call was made and that the offset was not 0
      # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
      assert_called(Datadog.DataStreams.Integrations.Kafka.track_produce(^topic, 0, offset))
      assert offset >= 1
    end
  end
end
