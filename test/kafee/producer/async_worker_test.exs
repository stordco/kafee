defmodule Kafee.Producer.AsyncWorkerTest do
  use Kafee.KafkaCase

  alias Kafee.Producer.AsyncWorker

  setup %{brod_client_id: brod_client_id} do
    topic = to_string(brod_client_id)
    :ok = KafkaCase.create_kafka_topic(topic, 1)

    opts = [
      brod_client_id: brod_client_id,
      topic: topic,
      partition: 0
    ]

    pid = start_supervised!({AsyncWorker, opts})

    on_exit(fn ->
      KafkaCase.delete_kafka_topic(topic)
    end)

    {:ok, %{topic: topic, partition: 0, pid: pid}}
  end

  describe "queue/2" do
    test "queue a list of messages will send them", %{pid: pid} do
      # This should create enough messages to require batching
      messages = for num <- 1..100_000, do: %{key: to_string(num), value: to_string(num)}
      assert :ok = AsyncWorker.queue(pid, messages)

      # Ensure we are empty of sending any messages.
      Process.sleep(2_500)
      wait_for_empty_mailbox(pid)

      process_state = :sys.get_state(pid)

      assert 0 == :queue.len(process_state.queue)
    end
  end

  defp wait_for_empty_mailbox(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, 0} ->
        :ok

      _ ->
        Process.sleep(100)
        wait_for_empty_mailbox(pid)
    end
  end
end
