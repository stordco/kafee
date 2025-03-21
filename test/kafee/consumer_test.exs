defmodule Kafee.ConsumerTest do
  use Kafee.KafkaCase

  describe "start_link/2" do
    test "validates options" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Kafee.Consumer.start_link(__MODULE__,
                 adapter: 101
               )
    end

    test "starts the adapter process tree", %{topic: topic} do
      assert {:ok, pid} =
               Kafee.Consumer.start_link(MyConsumer,
                 otp_app: :kafee,
                 adapter: Kafee.Consumer.BroadwayAdapter,
                 host: Kafee.KafkaApi.host(),
                 port: Kafee.KafkaApi.port(),
                 consumer_group_id: Kafee.KafkaApi.generate_consumer_group_id(),
                 topic: topic
               )

      assert is_pid(pid)
    end

    test "starts nothing if no adapter is set", %{topic: topic} do
      assert :ignore =
               Kafee.Consumer.start_link(MyConsumer,
                 otp_app: :kafee,
                 adapter: nil,
                 host: Kafee.KafkaApi.host(),
                 port: Kafee.KafkaApi.port(),
                 consumer_group_id: Kafee.KafkaApi.generate_consumer_group_id(),
                 topic: topic
               )
    end
  end
end
