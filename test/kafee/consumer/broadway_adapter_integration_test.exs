defmodule Kafee.Consumer.BroadwayAdapterIntegrationTest do
  use Kafee.KafkaCase

  defmodule MyConsumer do
    use Kafee.Consumer,
      adapter: {Kafee.Consumer.BroadwayAdapter, []}

    def handle_message(%Kafee.Consumer.Message{} = message) do
      test_pid = Application.get_env(:kafee, :test_pid, self())
      send(test_pid, {:consume_message, message})
    end
  end

  defmodule MyConsumerBatched do
    use Kafee.Consumer,
      adapter:
        {Kafee.Consumer.BroadwayAdapter,
         [
           batching: [
             concurrency: 2,
             size: 5,
             timeout: 10,
             async_run: true
           ]
         ]}

    def handle_message(%Kafee.Consumer.Message{} = message) do
      test_pid = Application.fetch_env!(:kafee, :test_pid)
      send(test_pid, {:consume_message, message, self()})
    end
  end

  describe "consumer without batching" do
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
  end

  describe "consumer with batching" do
    setup %{topic: topic} do
      Application.put_env(:kafee, :test_pid, self())

      start_supervised!(
        {MyConsumerBatched,
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

    test "it processes messages asynchronously in batches", %{brod_client_id: brod, topic: topic} do
      for i <- 1..100 do
        :ok = :brod.produce_sync(brod, topic, :hash, "key-#{i}", "test value")
      end

      task_pids =
        for i <- 1..100 do
          key = "key-#{i}"
          assert_receive {:consume_message, %Kafee.Consumer.Message{key: ^key}, from_pid}
          from_pid
        end

      # assert they were done asynchronously
      assert 100 == task_pids |> Enum.uniq() |> length
    end
  end
end
