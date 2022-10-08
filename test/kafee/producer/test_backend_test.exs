defmodule Kafee.Producer.TestBackendTest do
  use Kafee.KafkaCase

  defmodule TestProducer do
    use Kafee.Producer, producer_backend: Kafee.Producer.TestBackend
  end

  setup do
    start_supervised!({TestProducer, []})
    :ok
  end

  describe "produce/2" do
    test "sends messages" do
      messages =
        for num <- 1..1_000 do
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
    import Kafee.Testing

    test "it asserts all keys on a message" do
      message = %Kafee.Producer.Message{
        key: "test-key",
        value: "test-value",
        topic: "test-topic",
        partition: 0,
        partition_fun: :hash
      }

      assert :ok = TestProducer.produce([message])
      assert_producer_message(TestProducer, message)
    end

    test "it asserts partial keys on a message" do
      message = %Kafee.Producer.Message{
        key: "test-key-go-weeeeeee",
        value: "test-value-blablabla",
        topic: "test-topic-but-different",
        partition: 0
      }

      assert :ok = TestProducer.produce([message])
      assert_producer_message(TestProducer, %{key: "test-key-go-weeeeeee"})
    end

    test "it gets a super cool error message" do
      message = %Kafee.Producer.Message{
        key: "test-key-no-go",
        value: "test-value-mega-failure",
        topic: "local-dev-machine",
        partition: 0
      }

      assert :ok = TestProducer.produce([message])

      assert_raise ExUnit.AssertionError, ~r/Message matching the map given was not found/, fn ->
        assert_producer_message(TestProducer, %{key: "failure"})
      end
    end
  end
end
