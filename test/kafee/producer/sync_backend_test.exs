defmodule Kafee.Producer.SyncBackendTest do
  use Kafee.KafkaCase

  alias Kafee.Producer.{Config, Message, SyncBackend}

  setup %{topic: topic} do
    config = Config.new(producer: MyProducer, topic: topic)
    start_supervised!({Config, config})
    {:ok, %{config: config}}
  end

  describe "init/1" do
    test "starts brod child", %{config: config} do
      assert {:ok, _pid} = start_supervised({SyncBackend, config})
    end

    test "raises when given invalid config" do
      assert_raise ArgumentError, fn ->
        SyncBackend.init([])
      end
    end
  end

  setup %{brod_client_id: brod_client_id} do
    topic = to_string(brod_client_id)
    :ok = KafkaCase.create_kafka_topic(topic, 4)

    pid =
      start_supervised!(
        {TestProducer,
         [
           endpoints: KafkaCase.brod_endpoints(),
           topic: topic,
           brod_client_opts: KafkaCase.brod_client_config()
         ]}
      )

    on_exit(fn ->
      KafkaCase.delete_kafka_topic(topic)
    end)

    {:ok, %{pid: pid}}
  end

  describe "produce/2" do
    test "sends messages via :brod.produce_sync/5", %{config: config, topic: topic} do
      spy(:brod)
      start_supervised!({SyncBackend, config})

      messages = [
        %Message{topic: topic, partition: 0, key: "key", value: "value"},
        %Message{topic: topic, partition: 0, key: "key", value: "value"}
      ]

      assert :ok = SyncBackend.produce(config, messages)
      assert_called(:brod.produce_sync(_brod_client_id, _topic, _partition, _key, _message), 2)
    end

    test "returns errors from brod", %{config: config} do
      spy(:brod)
      start_supervised!({SyncBackend, config})
      message = %Message{topic: nil, partition: 0, key: "key", value: "value"}

      assert {:error, :unknown_topic_or_partition} = SyncBackend.produce(config, [message])
      assert_called(:brod.produce_sync(_brod_client_id, _topic, _partition, _key, _message), 1)
    end
  end
end
