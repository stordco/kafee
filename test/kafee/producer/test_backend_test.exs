defmodule Kafee.Producer.TestBackendTest do
  use Kafee.KafkaCase

  defmodule MyProducer do
    use Kafee.Producer,
      producer_backend: Kafee.Producer.TestBackend,
      partition_fun: :random
  end

  setup %{topic: topic} do
    Application.put_env(:kafee, :test_process, self())
    Application.put_env(:kafee, :producer, topic: topic)

    start_supervised!(MyProducer)
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

      assert :ok = MyProducer.produce(messages)
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

      assert :ok = MyProducer.produce([message])
      assert_receive {:kafee_message, ^message}
    end

    test "it decodes messages before sending to test pid" do
      spy(Kafee.NilEncoderDecoder)

      message = %Kafee.Producer.Message{
        key: "test-key",
        value: "test-value",
        topic: "test-topic",
        partition: 0,
        partition_fun: :hash
      }

      assert :ok = MyProducer.produce([message])
      assert_receive {:kafee_message, ^message}
      assert_called_once(Kafee.NilEncoderDecoder.decode!("test-value", _config))
    end
  end
end
