defmodule Kafee.Consumer.BrodMonitorTest do
  use Kafee.KafkaCase
  alias Kafee.Consumer.BrodMonitor

  defmodule MyProducer do
    use Kafee.Producer,
      adapter: Kafee.Producer.AsyncAdapter,
      partition_fun: :random

    def publish(_type, messages) do
      :ok = produce(messages)
    end
  end

  defmodule MyLaggyConsumer do
    use Kafee.Consumer,
      adapter: {Kafee.Consumer.BroadwayAdapter, []}

    def handle_message(%Kafee.Consumer.Message{} = message) do
      test_pid = Application.get_env(:kafee, :test_pid, self())
      # Each message processing is slow
      Process.sleep(100)
      send(test_pid, {:consume_message, message})
    end
  end

  setup %{topic: topic} do
    start_supervised!(
      {MyProducer,
       [
         host: KafkaApi.host(),
         port: KafkaApi.port(),
         topic: topic
       ]}
    )

    [topic: topic]
  end

  setup %{topic: topic} do
    consumer_group_id = KafkaApi.generate_consumer_group_id()

    [consumer_group_id: consumer_group_id]
  end

  describe "get_consumer_lag/5" do
    setup %{topic: topic, consumer_group_id: consumer_group_id} do
      Application.put_env(:kafee, :test_pid, self())

      consumer_pid =
        start_supervised!(
          {MyLaggyConsumer,
           [
             host: KafkaApi.host(),
             port: KafkaApi.port(),
             topic: topic,
             consumer_group_id: consumer_group_id
           ]}
        )

      Process.sleep(10_000)
      [consumer_pid: consumer_pid]
    end

    test "should correctly handle zero consumed case", %{
      brod_client_id: brod_client_id,
      topic: topic,
      partitions: partitions,
      consumer_group_id: consumer_group_id
    } do
      assert :ok =
               MyProducer.publish(:some_type, [
                 %Kafee.Producer.Message{
                   key: "some_key",
                   value: %{"some" => "message", "test_pid" => inspect(self())} |> Jason.encode!(),
                   topic: topic,
                   partition: 0
                 }
               ])

      partitions_list = Enum.map(0..(partitions - 1), & &1)
      assert :ok = poll_until_offset_tick(topic, partitions_list, [{0, 1}])

      assert {:ok, %{}} =
               BrodMonitor.get_consumer_lag(brod_client_id, Kafee.BrodApi.endpoints(), topic, consumer_group_id)
    end

    test "should correctly return consumer lag", %{
      brod_client_id: brod_client_id,
      topic: topic,
      partitions: partitions,
      consumer_group_id: consumer_group_id
    } do
      # producing 100 messages
      # since LaggyConsumer takes some time to process each message, we'll see lags
      for i <- 1..100 do
        :ok = :brod.produce_sync(brod_client_id, topic, :hash, "key-#{i}", "test value")
      end

      assert_receive {:consume_message, _}

      partitions_list = Enum.map(0..(partitions - 1), & &1)
      assert :ok = poll_until_offset_tick(topic, partitions_list, [{0, 100}])

      # wait a bit for consumer lag to build up
      Process.sleep(100)

      assert {:ok, %{0 => lag}} =
               BrodMonitor.get_consumer_lag(brod_client_id, Kafee.BrodApi.endpoints(), topic, consumer_group_id)

      assert lag > 20
    end
  end

  defp poll_until_offset_tick(topic, partitions_list, expected_result, attempt_left \\ 5)
  defp poll_until_offset_tick(_topic, _partitions_list, _expected_result, 0), do: {:error, :timeout}

  defp poll_until_offset_tick(topic, partitions_list, expected_result, attempt_left) do
    case BrodMonitor.get_latest_offsets(Kafee.BrodApi.endpoints(), topic, partitions_list, []) do
      ^expected_result ->
        :ok

      _ ->
        Process.sleep(100)
        poll_until_offset_tick(topic, partitions_list, expected_result, attempt_left - 1)
    end
  end
end
