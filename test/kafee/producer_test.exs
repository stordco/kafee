defmodule Kafee.ProducerTest do
  use Kafee.BrodCase, async: false

  describe "doctest" do
    setup do
      start_supervised!(MyProducer)
      :ok
    end

    doctest Kafee.Producer
  end

  describe "__using__/1 init/1" do
    test "allows setting config via using macro" do
      defmodule MyTestProducer do
        use Kafee.Producer,
          otp_app: :kafee,
          adapter: Kafee.Producer.TestAdapter,
          topic: "my super-amazing-test-topic",
          partition_fun: :random
      end

      start_supervised!(MyTestProducer)
      config = :ets.lookup_element(:kafee_config, MyTestProducer, 2)
      assert "my super-amazing-test-topic" == config[:topic]
    end

    test "allows setting config via init opts", %{topic: topic} do
      start_supervised({MyProducer, topic: topic})
      config = :ets.lookup_element(:kafee_config, MyProducer, 2)
      assert ^topic = config[:topic]
    end
  end

  describe "__using__/1 produce/1" do
    test "allows sending a single message", %{topic: topic} do
      spy(Kafee.Producer)
      start_supervised(MyProducer)

      message = BrodApi.generate_producer_message(topic)
      assert :ok = MyProducer.produce(message)

      # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
      assert_called_once(Kafee.Producer.produce(MyProducer, [^message]))
    end

    test "allows sending a list of messages", %{topic: topic} do
      spy(Kafee.Producer)
      start_supervised(MyProducer)

      messages = BrodApi.generate_producer_message_list(topic, 2)
      assert :ok = MyProducer.produce(messages)

      # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
      assert_called_once(Kafee.Producer.produce(MyProducer, ^messages))
    end
  end

  describe "produce/2" do
    test "sends messages to the producer", %{topic: topic} do
      spy(Kafee.Producer.TestAdapter)
      start_supervised({MyProducer, adapter: Kafee.Producer.TestAdapter})

      message = BrodApi.generate_producer_message(topic)
      assert :ok = Kafee.Producer.produce(MyProducer, [message])

      # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
      assert_called_once(Kafee.Producer.TestAdapter.produce([^message], MyProducer, _options))
    end
  end
end
