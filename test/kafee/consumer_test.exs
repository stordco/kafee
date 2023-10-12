defmodule Kafee.ConsumerTest do
  use Kafee.BrodCase, async: false

  describe "start_link/2" do
    test "validates options" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Kafee.Consumer.start_link(__MODULE__,
                 adapter: 101
               )
    end

    test "starts the adapter process tree" do
      topic = Kafee.KafkaApi.generate_topic()
      :ok = Kafee.KafkaApi.create_topic(topic)

      assert {:ok, pid} =
               Kafee.Consumer.start_link(MyConsumer,
                 adapter: Kafee.Consumer.BroadwayAdapter,
                 host: Kafee.KafkaApi.host(),
                 port: Kafee.KafkaApi.port(),
                 consumer_group_id: Kafee.KafkaApi.generate_consumer_group_id(),
                 topic: topic
               )

      assert is_pid(pid)
    end
  end
end
