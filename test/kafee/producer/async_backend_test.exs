defmodule Kafee.Producer.AsyncBackendTest do
  use Kafee.KafkaCase

  defmodule MyProducer do
    use Kafee.Producer,
      producer_backend: Kafee.Producer.AsyncBackend,
      partition_fun: :random
  end

  setup %{topic: topic} do
    Application.put_env(:kafee, :producer, topic: topic)

    spy(Kafee.Producer.AsyncWorker)
    start_supervised!(MyProducer)
    :ok
  end

  describe "produce/2" do
    test "sends messages" do
      messages =
        for num <- 1..5 do
          %Kafee.Producer.Message{
            key: to_string(num),
            value: to_string(num)
          }
        end

      assert :ok = MyProducer.produce(messages)
      assert_called(Kafee.Producer.AsyncWorker.queue(_pid, _messages), 1)
    end
  end
end
