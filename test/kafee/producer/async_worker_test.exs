defmodule Kafee.Producer.AsyncWorkerTest do
  use Kafee.KafkaCase

  alias Kafee.Producer.AsyncWorker

  setup %{brod_client_id: brod_client_id, topic: topic} do
    pid = start_supervised!({AsyncWorker, [
      brod_client_id: brod_client_id,
      topic: topic,
      partition: 0,
      send_interval: 1
    ]})

    {:ok, %{pid: pid}}
  end

  describe "queue/2" do
    test "queue a list of messages will send them", %{pid: pid} do
      assert :ok = AsyncWorker.queue(pid, [%{key: "1", value: "1"}, %{key: "2", value: "2"}])
    end
  end
end
