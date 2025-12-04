defmodule Kafee.Consumer.BrodAdapterIntegrationTest do
  use Kafee.KafkaCase

  defmodule MyConsumer do
    use Kafee.Consumer,
      adapter: Kafee.Consumer.BrodAdapter

    def handle_message(%Kafee.Consumer.Message{} = message) do
      test_pid = Application.get_env(:kafee, :test_pid, self())

      send(test_pid, {:consume_message, message})
    end
  end

  defmodule MyConsumerWithOffsetReset do
    use Kafee.Consumer,
      adapter: {Kafee.Consumer.BrodAdapter, offset_reset_policy: :reset_to_earliest}

    def handle_message(%Kafee.Consumer.Message{} = message) do
      test_pid = Application.get_env(:kafee, :test_pid, self())
      send(test_pid, {:consume_message, message})
    end
  end

  setup %{topic: topic} do
    Application.put_env(:kafee, :test_pid, self())

    start_supervised!(
      {MyConsumer,
       [
         host: KafkaApi.host(),
         port: KafkaApi.port(),
         topic: topic,
         consumer_group_id: KafkaApi.generate_consumer_group_id()
       ]}
    )

    Process.sleep(10_000)

    :ok
  end

  test "it processes messages", %{brod_client_id: brod, topic: topic} do
    for i <- 1..100 do
      :ok = :brod.produce_sync(brod, topic, :hash, "key-#{i}", "test value")
    end

    for i <- 1..100 do
      key = "key-#{i}"
      assert_receive {:consume_message, %Kafee.Consumer.Message{key: ^key}}
    end
  end

  test "it can be configured with offset_reset_policy", %{topic: topic, brod_client_id: brod} do
    # Create a new topic for this test to avoid interference
    test_topic = "#{topic}-offset-reset"
    consumer_group_id = KafkaApi.generate_consumer_group_id()

    # Start consumer with offset_reset_policy
    {:ok, pid} =
      start_supervised(
        {MyConsumerWithOffsetReset,
         [
           host: KafkaApi.host(),
           port: KafkaApi.port(),
           topic: test_topic,
           consumer_group_id: consumer_group_id
         ]}
      )

    Process.sleep(2_000)

    # Produce a message to verify the consumer works
    :ok = :brod.produce_sync(brod, test_topic, :hash, "offset-test-key", "test value")

    # The consumer should start successfully with the offset_reset_policy configuration
    # and be able to consume messages
    assert_receive {:consume_message, %Kafee.Consumer.Message{key: "offset-test-key"}}, 5_000
    assert Process.alive?(pid)
  end
end
