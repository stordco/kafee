defmodule Kafee.Producer.AsyncAdapterTest do
  use Kafee.KafkaCase

  alias Kafee.Producer.{AsyncWorker, Message}

  defmodule MyProducer do
    use Kafee.Producer,
      otp_app: :kafee,
      adapter: Kafee.Producer.AsyncAdapter,
      encoder: Kafee.JasonEncoderDecoder,
      partition_fun: :random
  end

  setup do
    spy(:brod)
    on_exit(fn -> restore(:brod) end)

    spy(Kafee.Producer.AsyncWorker)
    on_exit(fn -> restore(Kafee.Producer.AsyncWorker) end)

    spy(Datadog.DataStreams.Integrations.Kafka)
    on_exit(fn -> restore(Datadog.DataStreams.Integrations.Kafka) end)

    :ok
  end

  setup %{topic: topic} do
    start_supervised!(
      {MyProducer,
       [
         host: BrodApi.host(),
         port: BrodApi.port(),
         topic: topic
       ]}
    )

    :ok
  end

  describe "partitions/2" do
    test "returns a list of valid partitions" do
      options = :ets.lookup_element(:kafee_config, MyProducer, 2)
      partitions = Kafee.Producer.AsyncAdapter.partitions(MyProducer, options)
      assert [0] = partitions
    end
  end

  describe "produce/2" do
    test "queues messages to the async worker", %{topic: topic} do
      messages = BrodApi.generate_producer_message_list(topic, 5)

      assert :ok = MyProducer.produce(messages)

      assert_called_once(Kafee.Producer.AsyncWorker.queue(_pid, _messages))
    end

    test "ran the message normalization pipeline", %{topic: topic} do
      spy(Message)

      message = BrodApi.generate_producer_message(topic)
      assert :ok = MyProducer.produce(message)

      # credo:disable-for-lines:5 Credo.Check.Readability.NestedFunctionCalls
      assert_called_once(Message.set_module_values(^message, MyProducer, _options))
      assert_called_once(Message.encode(^message, MyProducer, _options))
      assert_called_once(Message.partition(_message, MyProducer, _options))
      assert_called_once(Message.set_request_id_from_logger(_message))
      assert_called_once(Message.validate!(_message))
    end

    test "reuses async worker processes", %{topic: topic} do
      # Send original messages to start the worker
      messages = BrodApi.generate_producer_message_list(topic, 5)
      assert :ok = MyProducer.produce(messages)
      assert_called_once(AsyncWorker.queue(_pid, _messages))

      {:via, Registry, {registry_name, registry_key}} = AsyncWorker.process_name(MyProducer.BrodClient, topic, 0)
      assert [{pid, _value}] = Registry.lookup(registry_name, registry_key)
      assert is_pid(pid)

      # Send more messages
      messages = BrodApi.generate_producer_message_list(topic, 5)
      assert :ok = MyProducer.produce(messages)
      assert_called(AsyncWorker.queue(_pid, _messages), 2)

      # Assert there is still only a single async worker process
      {:via, Registry, {registry_name, registry_key}} = AsyncWorker.process_name(MyProducer.BrodClient, topic, 0)
      assert [{pid, _value}] = Registry.lookup(registry_name, registry_key)
      assert is_pid(pid)
    end
  end
end
