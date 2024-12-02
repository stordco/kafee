defmodule Kafee.Consumer.BroadwayAdapterIntegrationTest do
  use Kafee.KafkaCase

  defmodule MyConsumer do
    use Kafee.Consumer,
      adapter: {Kafee.Consumer.BroadwayAdapter, []}

    def handle_message(%Kafee.Consumer.Message{} = message) do
      test_pid = Application.get_env(:kafee, :test_pid, self())
      send(test_pid, {:consume_message, message})
    end
  end

  defmodule FakeBuffy do
    use GenServer

    def start_link(args) do
      GenServer.start_link(__MODULE__, args)
    end

    def init([timeout, message]) do
      Process.send_after(self(), :timeout, timeout)
      {:ok, %{timeout: timeout, message: message}}
    end

    def handle_info(:timeout, %{message: message} = state) do
      raise("Error - timeout for #{message.key}")
      {:noreply, state}
    end
  end

  defmodule TestDynamicSupervisor do
    use DynamicSupervisor

    def start_link(_) do
      DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
    end

    def init(_) do
      DynamicSupervisor.init(strategy: :one_for_one)
    end

    def start_child({timeout, message}) do
      spec = {FakeBuffy, [timeout, message]}
      DynamicSupervisor.start_child(__MODULE__, spec)
    end
  end

  defmodule MyConsumerBatched do
    use Kafee.Consumer,
      adapter:
        {Kafee.Consumer.BroadwayAdapter,
         [
           batching: [
             concurrency: 2,
             size: 5,
             timeout: 10,
             async_run: true
           ]
         ]}

    def handle_message(%Kafee.Consumer.Message{} = message) do
      test_pid = Application.fetch_env!(:kafee, :test_pid)

      cond do
        String.starts_with?(message.key, "key-fail") ->
          raise "Error handling a message for #{message.key}"

        String.starts_with?(message.key, "timeout-fail") ->
          TestDynamicSupervisor.start_child({5000, message.key})

        true ->
          nil
      end

      send(test_pid, {:consume_message, message, self()})
    end

    def handle_failure(error, message) do
      test_pid = Application.fetch_env!(:kafee, :test_pid)
      send(test_pid, {:error_reason, inspect(error)})
      send(test_pid, {:error_messages, message})
    end
  end

  describe "Consumer with default single sized batching" do
    setup %{topic: topic} do
      Application.put_env(:kafee, :test_pid, self())

      start_supervised!(
        TestDynamicSupervisor,
        {MyConsumer,
         [
           host: KafkaApi.host(),
           port: KafkaApi.port(),
           topic: topic,
           consumer_group_id: KafkaApi.generate_consumer_group_id()
         ]}
      )

      Process.sleep(10_000)

      :ok
    end

    test "it processes messages", %{brod_client_id: brod, topic: topic} do
      for i <- 1..100 do
        :ok = :brod.produce_sync(brod, topic, :hash, "key-#{i}", "test value")
      end

      for i <- 1..100 do
        key = "key-#{i}"
        assert_receive {:consume_message, %Kafee.Consumer.Message{key: ^key}}
      end
    end
  end

  describe "Consumer with customized batching" do
    setup %{topic: topic} do
      Application.put_env(:kafee, :test_pid, self())

      start_supervised!(
        {MyConsumerBatched,
         [
           host: KafkaApi.host(),
           port: KafkaApi.port(),
           topic: topic,
           consumer_group_id: KafkaApi.generate_consumer_group_id()
         ]}
      )

      Process.sleep(10_000)

      :ok
    end

    test "it processes messages asynchronously in batches", %{brod_client_id: brod, topic: topic} do
      for i <- 1..100 do
        :ok = :brod.produce_sync(brod, topic, :hash, "key-#{i}", "test value")
      end

      task_pids =
        for i <- 1..100 do
          key = "key-#{i}"
          assert_receive {:consume_message, %Kafee.Consumer.Message{key: ^key}, from_pid}
          from_pid
        end

      # assert they were done asynchronously
      assert 100 == task_pids |> Enum.uniq() |> length
    end

    test "it handles errors and bubbles just the messages with errors up to the consumer handle_failure", %{
      brod_client_id: brod,
      topic: topic
    } do
      :ok = :brod.produce_sync(brod, topic, :hash, "key-fail-1", "test value 1")
      :ok = :brod.produce_sync(brod, topic, :hash, "key-fail-2", "test value 2")

      for i <- 1..100 do
        :ok = :brod.produce_sync(brod, topic, :hash, "key-#{i}", "test value")
      end

      task_pids =
        for i <- 1..100 do
          key = "key-#{i}"
          assert_receive {:consume_message, %Kafee.Consumer.Message{key: ^key}, from_pid}
          from_pid
        end

      # assert they were done asynchronously
      assert 100 == task_pids |> Enum.uniq() |> length

      assert_receive {:error_reason, "%RuntimeError{message: \"Error handling a message for key-fail-1\"}"}
      assert_receive {:error_reason, "%RuntimeError{message: \"Error handling a message for key-fail-2\"}"}
    end

    test "it handles asynchronous failures for concurrent process chains", %{
      brod_client_id: brod,
      topic: topic
    } do
      :ok = :brod.produce_sync(brod, topic, :hash, "timeout-fail-1", "test value 1")
      :ok = :brod.produce_sync(brod, topic, :hash, "timeout-fail-2", "test value 2")

      for i <- 1..100 do
        :ok = :brod.produce_sync(brod, topic, :hash, "key-#{i}", "test value")
      end

      task_pids =
        for i <- 1..100 do
          key = "key-#{i}"
          assert_receive {:consume_message, %Kafee.Consumer.Message{key: ^key}, from_pid}
          from_pid
        end

      Process.sleep(10_000)

      bpid =
        Process.whereis(
          Kafee.Consumer.BroadwayAdapterIntegrationTest.MyConsumerBatched.Broadway.BatchProcessor_default_0
        )

      assert Process.alive?(bpid)
      # assert they were done asynchronously
      assert 100 == task_pids |> Enum.uniq() |> length

      assert_receive {:error_reason, "%RuntimeError{message: \"Error - timeout for timeout-fail-1\"}"}
      assert_receive {:error_reason, "%RuntimeError{message: \"Error - timeout for timeout-fail-2\"}"}
    end
  end
end
