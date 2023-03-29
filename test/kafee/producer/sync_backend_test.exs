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

  describe "partition/2" do
    test "calls :brod.get_partitions_count/2", %{config: config, topic: topic} do
      spy(:brod)
      start_supervised!({SyncBackend, config})
      message = %Message{topic: topic, partition_fun: :random}

      assert {:ok, _partition} = SyncBackend.partition(config, message)
      assert_called :brod.get_partitions_count(brod_client_id, _topic)
    end

    test "calls :brod_utils.make_part_fun/1", %{config: config, topic: topic} do
      spy(:brod_utils)
      start_supervised!({SyncBackend, config})
      message = %Message{topic: topic, partition_fun: :random}

      assert {:ok, _partition} = SyncBackend.partition(config, message)
      assert_called :brod_utils.make_part_fun(_partition_fun)
    end
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
      assert_called :brod.produce_sync(_brod_client_id, _topic, _partition, _key, _message), 2
    end

    test "returns errors from brod", %{config: config} do
      spy(:brod)
      start_supervised!({SyncBackend, config})
      message = %Message{topic: nil, partition: 0, key: "key", value: "value"}

      assert {:error, :unknown_topic_or_partition} = SyncBackend.produce(config, [message])
      assert_called :brod.produce_sync(_brod_client_id, _topic, _partition, _key, _message), 1
    end
  end
end
