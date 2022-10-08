defmodule Kafee.Producer.SyncBackendTest do
  use Kafee.KafkaCase

  defmodule TestProducer do
    use Kafee.Producer, producer_backend: Kafee.Producer.SyncBackend
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
           brod_client_opts: KafkaCase.brod_client_config(),
           kafee_async_worker_opts: [send_interval: 1]
         ]}
      )

    on_exit(fn ->
      KafkaCase.delete_kafka_topic(topic)
    end)

    {:ok, %{pid: pid}}
  end

  describe "produce/2" do
    test "sends messages" do
      messages =
        for num <- 1..10 do
          %Kafee.Producer.Message{
            key: to_string(num),
            value: to_string(num)
          }
        end

      assert :ok = TestProducer.produce(messages)
    end
  end
end
