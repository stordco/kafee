defmodule Kafee.Producer.TestBackendTest do
  use Kafee.KafkaCase

  defmodule TestProducer do
    use Kafee.Producer, producer_backend: Kafee.Producer.TestBackend
  end

  setup do
    Application.put_env(:kafee, :test_process, self())
    start_supervised!({TestProducer, []})
    :ok
  end

  describe "produce/2" do
    test "sends messages" do
      messages =
        for num <- 1..10 do
          %Kafee.Producer.Message{
            key: to_string(num),
            value: to_string(num),
            topic: "test",
            partition: 0
          }
        end

      assert :ok = TestProducer.produce(messages)
    end
  end

  describe "assert_message_produced/2" do
    test "it asserts all keys on a message" do
      message = %Kafee.Producer.Message{
        key: "test-key",
        value: "test-value",
        topic: "test-topic",
        partition: 0,
        partition_fun: :hash
      }

      assert :ok = TestProducer.produce([message])
      assert_receive {:kafee_message, ^message}
    end
  end
end
