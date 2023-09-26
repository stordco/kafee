defmodule Kafee.ProducerIntegrationTest do
  use Kafee.BrodCase

  import ExUnit.CaptureLog

  # Generally enough time for the worker to do what ever it needs to do.
  @wait_timeout 1000

  setup %{topic: topic} do
    start_supervised!(
      {MyIntegrationProducer,
       [
         hostname: KafkaApi.host(),
         port: KafkaApi.port(),
         topic: topic
       ]}
    )

    :ok
  end

  describe "large messages" do
    test "logs and continues" do
      message_fixture = File.read!("test/support/example/large_message.json")
      large_message = String.duplicate(message_fixture, 4)

      log =
        capture_log(fn ->
          assert :ok =
                   MyIntegrationProducer.produce([
                     %Kafee.Producer.Message{
                       key: "something_huge_above_4mb",
                       value: large_message,
                       topic: "wms-service",
                       partition: 0
                     }
                   ])

          Process.sleep(@wait_timeout)
        end)

      assert log =~ "Message in queue is too large"

      # At this point the brod client is offline and we have to wait 10 seconds
      # for the next message to be sent

      log =
        capture_log(fn ->
          assert :ok =
                   MyIntegrationProducer.produce([
                     %Kafee.Producer.Message{
                       key: "something_small",
                       value: "aaaa",
                       topic: "wms-service",
                       partition: 0
                     }
                   ])

          Process.sleep(@wait_timeout + 10_000)
        end)

      refute log =~ "Message in queue is too large"
      assert log =~ "brod producer process is currently down"
      assert log =~ "Successfully sent messages to Kafka"
    end
  end
end