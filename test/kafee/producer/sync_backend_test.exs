defmodule Kafee.Producer.SyncBackendTest do
  use Kafee.KafkaCase

  defmodule MyProducer do
    use Kafee.Producer,
      producer_backend: Kafee.Producer.SyncBackend,
      partition_fun: :random
  end

  setup %{topic: topic} do
    Application.put_env(:kafee, :producer, topic: topic)

    spy(:brod)
    start_supervised!(MyProducer)
    :ok
  end

  describe "produce/2" do
    test "sends messages via :brod.produce_sync/5", %{topic: topic} do
      messages = [
        %Kafee.Producer.Message{topic: topic, partition: 0, key: "key", value: "value"},
        %Kafee.Producer.Message{topic: topic, partition: 0, key: "key", value: "value"}
      ]

      assert :ok = MyProducer.produce(messages)
      assert_called(:brod.produce_sync(_brod_client_id, _topic, _partition, _key, _message), 2)
    end

    test "returns errors from brod" do
      message = %Kafee.Producer.Message{topic: nil, partition: 0, key: "key", value: "value"}

      # We use the `Kafee.Producer.produce/2` function to bypass normalization
      assert {:error, :unknown_topic_or_partition} = Kafee.Producer.produce([message], MyProducer)
      assert_called(:brod.produce_sync(_brod_client_id, _topic, _partition, _key, _message), 1)
    end
  end
end
