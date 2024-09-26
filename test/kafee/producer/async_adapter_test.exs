defmodule Kafee.Producer.AsyncAdapterTest do
  use Kafee.KafkaCase
  import ExUnit.CaptureLog

  alias Kafee.Producer.{AsyncWorker, Message}

  defmodule MyProducer do
    use Kafee.Producer,
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
    defp assert_registry_lookup_pid(brod_client, topic, partition) do
      {:via, Registry, {registry_name, registry_key}} =
        AsyncWorker.process_name(brod_client, topic, partition)

      [{pid, _value}] = Registry.lookup(registry_name, registry_key)
      assert is_pid(pid)
      pid
    end

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

      assert_registry_lookup_pid(MyProducer.BrodClient, topic, 0)

      # Send more messages
      messages = BrodApi.generate_producer_message_list(topic, 5)
      assert :ok = MyProducer.produce(messages)
      assert_called(AsyncWorker.queue(_pid, _messages), 2)

      # Assert there is still only a single async worker process
      assert_registry_lookup_pid(MyProducer.BrodClient, topic, 0)
    end

    @tag capture_log: true
    test "uses different async worker processes for different partitions", %{topic: topic} do
      # messages list with all unique partitions
      messages = BrodApi.generate_producer_partitioned_message_list(topic, 5, 5)

      capture_log(fn ->
        assert :ok = MyProducer.produce(messages)
      end)

      assert_called(AsyncWorker.queue(_pid, _messages), 5)

      worker_pids =
        for x <- 0..4 do
          assert_registry_lookup_pid(MyProducer.BrodClient, topic, x)
        end

      assert 5 == worker_pids |> Enum.uniq() |> length()

      # Send more messages through same 5 partitions
      messages = BrodApi.generate_producer_partitioned_message_list(topic, 5, 5)

      assert :ok = MyProducer.produce(messages)
      assert_called(AsyncWorker.queue(_pid, _messages), 10)

      # Assert no new worker processes got created
      worker_pids_2 =
        for x <- 0..4 do
          assert_registry_lookup_pid(MyProducer.BrodClient, topic, x)
        end

      assert worker_pids_2 |> MapSet.new() |> MapSet.equal?(MapSet.new(worker_pids))

      # clean up because kafka in test only has one partition, so errors happen
      capture_log(fn ->
        stop_supervised(MyProducer)
      end)
    end
  end
end
