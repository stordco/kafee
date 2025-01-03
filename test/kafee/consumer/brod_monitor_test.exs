defmodule Kafee.Consumer.BrodMonitorTest do
  use Kafee.KafkaCase
  alias Kafee.Consumer.{Adapter, BrodMonitor}

  defmodule MyProducer do
    use Kafee.Producer,
      adapter: Kafee.Producer.AsyncAdapter,
      partition_fun: :random

    def publish(_type, messages) do
      :ok = produce(messages)
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

    :ok
  end

  setup(%{topic: topic}) do
    consumer_group_id = Kafee.KafkaApi.generate_consumer_group_id()

    consumer_pid =
      start_supervised!(%{
        id: MyConsumer,
        start:
          {Kafee.Consumer, :start_link,
           [
             MyConsumer,
             [
               adapter: Kafee.Consumer.BroadwayAdapter,
               host: Kafee.KafkaApi.host(),
               port: Kafee.KafkaApi.port(),
               consumer_group_id: consumer_group_id,
               topic: topic
             ]
           ]}
      })

    [consumer_pid: consumer_pid, consumer_group_id: consumer_group_id]
  end

  describe "get_consumer_lag/5" do
    test "should correctly handle zero consumed case", %{
      brod_client_id: brod_client_id,
      topic: topic,
      partitions: partitions,
      consumer_group_id: consumer_group_id
    } do
      assert :ok =
               MyProducer.publish(:some_type, [
                 %Kafee.Producer.Message{
                   key: "something_huge_above_4mb",
                   value: %{"some" => "message", "test_pid" => inspect(self())} |> Jason.encode!(),
                   topic: topic,
                   partition: 0
                 }
               ])

      partitions_list = Enum.map(0..(partitions - 1), & &1)
      poll_until_offset_tick(topic, partitions_list, [{0, 1}])

      assert {:ok, %{}} =
               BrodMonitor.get_consumer_lag(brod_client_id, Kafee.BrodApi.endpoints(), topic, consumer_group_id)
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
