defmodule Kafee.Consumer.BroadwayAdapterIntegrationTest do
  use Kafee.KafkaCase

  defmodule MyConsumer do
    use Kafee.Consumer,
      otp_app: :kafee,
      adapter: {Kafee.Consumer.BroadwayAdapter, []}

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
end
