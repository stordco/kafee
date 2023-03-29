defmodule Kafee.ProducerTest do
  use Kafee.BrodCase

  import Kafee.Producer

  alias Kafee.Producer.{Config, Message}

  setup do
    on_exit(fn -> Application.delete_env(:kafee, :producer) end)
    :ok
  end

  describe "doctest" do
    setup do
      patch(MyProducer, :produce, fn _ -> :ok end)
      start_supervised!(MyProducer)
      :ok
    end

    doctest Kafee.Producer
  end

  describe "init/1" do
    test "allows setting config via application env", %{topic: topic} do
      Application.put_env(:kafee, :producer, topic: topic)
      start_supervised!(MyProducer)
      assert topic == Config.get(MyProducer).topic
    end

    test "allows setting config via using macro" do
      defmodule MyTestProducer do
        use Kafee.Producer,
          producer_backend: Kafee.Producer.TestBackend,
          topic: "my super-amazing-test-topic"
      end

      start_supervised!(MyTestProducer)
      assert "my super-amazing-test-topic" == Config.get(MyTestProducer).topic
    end

    test "allows setting config via init opts", %{topic: topic} do
      start_supervised({MyProducer, topic: topic})
      assert topic == Config.get(MyProducer).topic
    end
  end

  describe "produce/1" do
    test "allows sending a single message", %{topic: topic} do
      message = %Message{key: "test", value: "test", topic: topic}

      spy(Kafee.Producer)
      start_supervised(MyProducer)
      assert :ok = MyProducer.produce(message)
      assert_called_once(Kafee.Producer.produce([message], _producer))
    end

    test "allows sending a list of messages", %{topic: topic} do
      messages = [
        %Message{key: "test", value: "test", topic: topic},
        %Message{key: "test2", value: "test2", topic: topic}
      ]

      spy(Kafee.Producer)
      start_supervised(MyProducer)
      assert :ok = MyProducer.produce(messages)
      assert_called_once(Kafee.Producer.produce(messages, _producer))
    end

    test "normalizes the data", %{topic: topic} do
      message = %Message{key: "test", value: "test", topic: topic}

      spy(Kafee.Producer)
      start_supervised(MyProducer)
      assert :ok = MyProducer.produce(message)
      assert_called_once(Kafee.Producer.normalize([message], MyProducer))
    end
  end

  describe "normalize/2" do
    test "uses the message topic if set", %{topic: topic} do
      message = %Message{key: "test", value: "test", topic: topic}
      start_supervised(MyProducer)
      assert [%{topic: ^topic}] = Kafee.Producer.normalize([message], MyProducer)
    end

    test "sets topic if not set in the message", %{topic: topic} do
      message = %Message{key: "test", value: "test"}
      start_supervised({MyProducer, [topic: topic]})
      assert [%{topic: ^topic}] = Kafee.Producer.normalize([message], MyProducer)
    end

    test "uses the partition function if set", %{topic: topic} do
      fun = fn _, _, _, _ -> {:ok, 12} end
      message = %Message{key: "test", value: "test", topic: topic, partition_fun: fun}
      start_supervised(MyProducer)
      assert [%{partition_fun: ^fun}] = Kafee.Producer.normalize([message], MyProducer)
    end

    test "sets partition function if not set in the message", %{topic: topic} do
      fun = fn _, _, _, _ -> {:ok, 12} end
      message = %Message{key: "test", value: "test", topic: topic}
      start_supervised({MyProducer, [partition_fun: fun]})
      assert [%{partition_fun: ^fun}] = Kafee.Producer.normalize([message], MyProducer)
    end

    test "uses the partition if set", %{topic: topic} do
      message = %Message{key: "test", value: "test", topic: topic, partition: 12}
      start_supervised(MyProducer)
      assert [%{partition: 12}] = Kafee.Producer.normalize([message], MyProducer)
    end

    test "sets the partition if not set in the message", %{topic: topic} do
      message = %Message{key: "test", value: "test", topic: topic}
      start_supervised(MyProducer)
      assert [%{partition: 0}] = Kafee.Producer.normalize([message], MyProducer)
    end
  end

  describe "validate_batch!/1" do
    test "validates each message", %{topic: topic} do
      messages = [
        %Kafee.Producer.Message{key: "test", value: "test", topic: topic, partition: 0},
        %Kafee.Producer.Message{key: "test2", value: "test2", topic: topic, partition: 0}
      ]

      spy(Kafee.Producer)
      start_supervised(MyProducer)
      assert ^messages = Kafee.Producer.validate_batch!(messages)
      assert_called(Kafee.Producer.validate!(_message), 2)
    end
  end

  describe "validate!/1" do
    @valid_message %Kafee.Producer.Message{
      key: "test",
      value: "test",
      topic: "test",
      partition: 0,
      headers: [{"one", "two"}]
    }

    test "raises on no topic" do
      assert_raise Kafee.Producer.ValidationError, "Message is missing a topic to send to.", fn ->
        Kafee.Producer.validate!(%{@valid_message | topic: nil})
      end
    end

    test "raises on no partition" do
      assert_raise Kafee.Producer.ValidationError, "Message is missing a partition to send to.", fn ->
        Kafee.Producer.validate!(%{@valid_message | partition: nil})
      end
    end

    test "raises on non string messages headers" do
      assert_raise Kafee.Producer.ValidationError, "Message header keys and values must be a binary value.", fn ->
        Kafee.Producer.validate!(%{@valid_message | headers: [{"one", 2}]})
      end
    end
  end

  describe "produce/2" do
    test "sends messages to the producer", %{topic: topic} do
      message = %Kafee.Producer.Message{key: "test", value: "test", topic: topic}

      spy(Kafee.Producer.TestBackend)
      start_supervised(MyProducer)
      assert :ok = Kafee.Producer.produce([message], MyProducer)
      assert_called_once(Kafee.Producer.TestBackend.produce(_config, [message]))
    end
  end
end
