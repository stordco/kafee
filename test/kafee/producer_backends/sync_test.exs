defmodule Kafee.SyncProducerBackendTest do
  use ExUnit.Case

  @topic "sync-producer-backend-test"

  setup do
    pid =
      start_supervised!(
        {Kafee.SyncProducerBackend,
         Kafee.KafkaCase.kafka_credentials() ++
           [
             producer_module: __MODULE__,
             topic: @topic
           ]}
      )

    {:ok, pid: pid}
  end

  test "sends message", %{pid: pid} do
    message = %Kafee.Message{key: "test-1", value: "test-value"}
    assert :ok = GenServer.call(pid, {:produce_messages, @topic, [message]})
  end
end
