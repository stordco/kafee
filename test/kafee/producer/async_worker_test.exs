defmodule Kafee.Producer.AsyncWorkerTest do
  use Kafee.KafkaCase

  alias Kafee.Producer.AsyncWorker

  setup %{brod_client_id: brod_client_id} do
    topic = to_string(brod_client_id)
    :ok = KafkaCase.create_kafka_topic(topic, 1)
    pid = start_supervised!({AsyncWorker, [brod_client_id, topic, 0, send_interval: 1]})

    on_exit(fn ->
      KafkaCase.delete_kafka_topic(topic)
    end)

    {:ok, %{topic: topic, pid: pid}}
  end

  describe "queue/2" do
    test "queue a list of messages will send them", %{pid: pid} do
      assert :ok = AsyncWorker.queue(pid, [%{key: "test", value: "test"}])
    end

    test "queue a single message will send it", %{pid: pid} do
      assert :ok = AsyncWorker.queue(pid, %{key: "test", value: "test"})
    end
  end
end
