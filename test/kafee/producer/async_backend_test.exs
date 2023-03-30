defmodule Kafee.Producer.AsyncBackendTest do
  use Kafee.KafkaCase

  setup %{topic: topic} do
    Application.put_env(:kafee, :producer,
      producer_backend: Kafee.Producer.AsyncBackend,
      topic: topic
    )

    start_supervised!(MyProducer)
    :ok
  end

  describe "produce/2" do
    test "sends messages" do
      messages =
        for num <- 1..10 do
          %Kafee.Producer.Message{
            key: to_string(num),
            value: to_string(num)
          }
        end

      assert :ok = MyProducer.produce(messages)
    end
  end
end
