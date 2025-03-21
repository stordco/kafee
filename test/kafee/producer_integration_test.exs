defmodule Kafee.ProducerIntegrationTest do
  use Kafee.KafkaCase

  import ExUnit.CaptureLog

  # Generally enough time for the worker to do what ever it needs to do.
  @wait_timeout 1_000

  defmodule MyProducer do
    use Kafee.Producer,
      otp_app: :kafee,
      adapter: Kafee.Producer.AsyncAdapter,
      partition_fun: :random
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

  describe "large messages" do
    test "logs and continues", %{topic: topic} do
      message_fixture = File.read!("test/support/example/large_message.json")
      large_message = String.duplicate(message_fixture, 10)

      log =
        capture_log(fn ->
          assert :ok =
                   MyProducer.produce([
                     %Kafee.Producer.Message{
                       key: "something_huge_above_4mb",
                       value: large_message,
                       topic: topic,
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
                   MyProducer.produce([
                     %Kafee.Producer.Message{
                       key: "something_small",
                       value: "aaaa",
                       topic: topic,
                       partition: 0
                     }
                   ])

          Process.sleep(@wait_timeout + 10_000)
        end)

      refute log =~ "Message in queue is too large"
      assert log =~ "Successfully sent messages to Kafka"
    end
  end
end
