defmodule Kafee.Producer.AsyncWorkerTest do
  use Kafee.KafkaCase

  import ExUnit.CaptureLog

  alias Kafee.Producer.AsyncWorker

  # Generally enough time for the worker to do what ever it needs to do.
  @wait_timeout 500

  setup do
    spy(:brod)
    on_exit(fn -> restore(:brod) end)
    :ok
  end

  setup %{topic: topic} do
    self = self()

    :telemetry.attach(
      topic,
      [:kafee, :queue],
      fn name, measurements, metadata, _ ->
        send(self, {:telemetry_event, name, measurements, metadata})
      end,
      nil
    )

    :ok
  end

  setup %{brod_client_id: brod_client_id, topic: topic} do
    worker_pid =
      start_supervised!(
        {AsyncWorker,
         [
           brod_client_id: brod_client_id,
           topic: topic,
           partition: 0,
           send_interval: 1
         ]}
      )

    state = :sys.get_state(worker_pid)
    {:ok, pid} = listen(topic, worker_pid)

    {:ok, %{pid: pid, state: state, worker_pid: worker_pid}}
  end

  describe "queue/2" do
    test "queue a list of messages will send them", %{pid: pid, topic: topic} do
      messages = BrodApi.generate_producer_message_list(topic, 2)
      assert :ok = AsyncWorker.queue(pid, messages)
      assert_receive {^topic, {GenServer, :cast, {:queue, ^messages}}}
    end
  end

  describe "handle_info :send" do
    test "does nothing on an empty queue", %{state: state} do
      assert 0 = :queue.len(state.queue)
      assert {:noreply, ^state} = AsyncWorker.handle_info(:send, state)
      refute_any_call(:brod.produce())
    end

    test "spawns send task if queue is not nil", %{state: state, topic: topic} do
      messages = BrodApi.generate_producer_message_list(topic, 2)
      state = %{state | queue: :queue.from_list(messages)}

      assert {:noreply, new_state} = AsyncWorker.handle_info(:send, state)
      refute is_nil(new_state.send_task)

      Process.sleep(@wait_timeout)

      assert_called_once(:brod.produce(_client_id, ^topic, 0, _key, ^messages))
    end

    test "does not spawn a send task if one already in flight", %{state: state, topic: topic} do
      messages = BrodApi.generate_producer_message_list(topic, 2)
      state = %{state | queue: :queue.from_list(messages), send_task: make_fake_task()}

      assert {:noreply, ^state} = AsyncWorker.handle_info(:send, state)
      refute_any_call(:brod.produce())
    end
  end

  describe "handle_info task_ref" do
    test ":ok removes sent messages from the queue", %{state: state, topic: topic} do
      task = make_fake_task()
      send_messages = BrodApi.generate_producer_message_list(topic, 4)
      remaining_messages = BrodApi.generate_producer_message_list(topic, 3)
      state = %{state | send_task: task, queue: :queue.from_list(send_messages ++ remaining_messages)}

      assert {:noreply, new_state} = AsyncWorker.handle_info({task.ref, {:ok, 4}}, state)
      assert ^remaining_messages = :queue.to_list(new_state.queue)
    end

    test ":ok emits telemetry of remaining messages", %{state: state, topic: topic} do
      task = make_fake_task()
      send_messages = BrodApi.generate_producer_message_list(topic, 4)
      remaining_messages = BrodApi.generate_producer_message_list(topic, 3)
      state = %{state | send_task: task, queue: :queue.from_list(send_messages ++ remaining_messages)}

      assert {:noreply, _new_state} = AsyncWorker.handle_info({task.ref, {:ok, 4}}, state)
      assert_receive {:telemetry_event, [:kafee, :queue], %{count: 3}, %{partition: 0, topic: ^topic}}
    end

    test "timeouts log error and retries sending messages", %{state: state} do
      task = make_fake_task()
      state = %{state | send_task: task}

      logs =
        capture_log(fn ->
          assert {:noreply, ^state} = AsyncWorker.handle_info({task.ref, {:error, :timeout}}, state)
        end)

      assert logs =~ "timeout"

      Process.sleep(@wait_timeout)
      assert_receive :send
    end

    @tag capture_log: true
    test "any single message too large gets logged and dropped from queue", %{pid: pid, topic: topic} do
      message_fixture = File.read!("test/support/example/large_message.json")
      large_message = String.duplicate(message_fixture, 4)

      message = %Kafee.Producer.Message{
        key: "something_huge_above_4mb",
        value: large_message,
        topic: "wms-service",
        partition: 0
      }

      log =
        capture_log(fn ->
          assert :ok = AsyncWorker.queue(pid, [message])
          Process.sleep(@wait_timeout)
        end)

      assert_called_once(:brod.produce(_client_id, ^topic, 0, _key, [^message]))
      assert log =~ "Message in queue is too large"

      async_worker_state = pid |> Patch.Listener.target() |> :sys.get_state()
      assert 0 == :queue.len(async_worker_state.queue)
    end

    test "any other tuple logs error and retries sending messages", %{state: state} do
      task = make_fake_task()
      state = %{state | send_task: task}

      logs =
        capture_log(fn ->
          assert {:noreply, ^state} = AsyncWorker.handle_info({task.ref, {:error, :internal_brod_error}}, state)
        end)

      assert logs =~ "error"
      assert logs =~ "internal_brod_error"

      Process.sleep(@wait_timeout)
      assert_receive :send
    end

    test "unknown processes log and do nothing", %{state: state} do
      task = make_fake_task()
      state = %{state | send_task: task}

      logs =
        capture_log(fn ->
          assert {:noreply, ^state} = AsyncWorker.handle_info({make_ref(), {:error, :random_message}}, state)
        end)

      assert logs =~ "unknown process"
      assert logs =~ "random_message"

      Process.sleep(@wait_timeout)
      refute_receive :send
    end
  end

  describe "handle_info :DOWN" do
    test "normal reasons clear the send_task state", %{state: state} do
      task = make_fake_task()
      state = %{state | send_task: task}

      assert {:noreply, new_state} = AsyncWorker.handle_info({:DOWN, task.ref, :process, task.pid, :normal}, state)
      assert is_nil(new_state.send_task)
    end

    test "any other reason logs error and retries sending messages", %{state: state} do
      task = make_fake_task()
      state = %{state | send_task: task}

      log =
        capture_log(fn ->
          assert {:noreply, new_state} = AsyncWorker.handle_info({:DOWN, task.ref, :process, task.pid, :kill}, state)
          assert is_nil(new_state.send_task)
        end)

      assert log =~ "Crash"

      Process.sleep(@wait_timeout)
      assert_receive :send
    end

    test "unknown processes log and do nothing", %{state: state} do
      task = make_fake_task()
      state = %{state | send_task: task}

      log =
        capture_log(fn ->
          assert {:noreply, new_state} = AsyncWorker.handle_info({:DOWN, make_ref(), :process, self(), :kill}, state)
          refute is_nil(new_state.send_task)
        end)

      assert log =~ "Crash"
      assert log =~ "unknown process"

      Process.sleep(@wait_timeout)
      refute_receive :send
    end
  end

  test "ignores unknown messages", %{state: state} do
    assert {:noreply, ^state} = AsyncWorker.handle_info(:unknown, state)
  end

  describe "handle_cast :queue" do
    test "adds messages to the queue", %{topic: topic, state: state} do
      messages = BrodApi.generate_producer_message_list(topic, 2)
      assert {:noreply, new_state} = AsyncWorker.handle_cast({:queue, messages}, state)
      assert ^messages = :queue.to_list(new_state.queue)
    end

    test "emits telemetry for queue length", %{topic: topic, state: state} do
      messages = BrodApi.generate_producer_message_list(topic, 2)
      assert {:noreply, _new_state} = AsyncWorker.handle_cast({:queue, messages}, state)
      assert_receive {:telemetry_event, [:kafee, :queue], %{count: 2}, %{partition: 0, topic: ^topic}}
    end

    test "sends :send message", %{topic: topic, state: state} do
      messages = BrodApi.generate_producer_message_list(topic, 2)
      assert {:noreply, _new_state} = AsyncWorker.handle_cast({:queue, messages}, state)
      Process.sleep(@wait_timeout)
      assert_receive :send
    end
  end

  describe "terminate" do
    test "gracefully exits with any empty queue and no in flight tasks", %{state: state} do
      assert is_nil(state.send_task)
      assert 0 = :queue.len(state.queue)

      logs =
        capture_log(fn ->
          assert :ok = AsyncWorker.terminate(:normal, state)
        end)

      assert logs =~ "empty queue"
    end

    test "waits for in flight tasks to complete", %{state: state, topic: topic} do
      remaining_messages = BrodApi.generate_producer_message_list(topic, 20)
      state = %{state | queue: :queue.from_list(remaining_messages)}

      assert :ok = AsyncWorker.terminate(:normal, state)
      assert_called_once(:brod.produce(_client_id, ^topic, 0, _key, ^remaining_messages))
    end

    test "waits for in flight send and sends remaining messages", %{state: state, topic: topic} do
      remaining_messages = BrodApi.generate_producer_message_list(topic, 20)
      task = make_fake_task()
      state = %{state | queue: :queue.from_list(remaining_messages), send_task: task, send_timeout: :infinity}

      Process.send_after(self(), {task.ref, {:ok, 0}}, 10)
      assert :ok = AsyncWorker.terminate(:normal, state)
      assert_called_once(:brod.produce(_client_id, ^topic, 0, _key, ^remaining_messages))
    end

    @tag capture_log: true
    test "waits for in flight error and retries sending messages", %{state: state, topic: topic} do
      remaining_messages = BrodApi.generate_producer_message_list(topic, 20)
      task = make_fake_task()
      state = %{state | queue: :queue.from_list(remaining_messages), send_task: task, send_timeout: :infinity}

      Process.send_after(self(), {task.ref, {:error, :internal_error}}, 10)
      assert :ok = AsyncWorker.terminate(:normal, state)
      assert_called_once(:brod.produce(_client_id, ^topic, 0, _key, ^remaining_messages))
    end

    test "waits for timeout and retries sending messages", %{state: state, topic: topic} do
      remaining_messages = BrodApi.generate_producer_message_list(topic, 20)
      task = make_fake_task()
      state = %{state | queue: :queue.from_list(remaining_messages), send_task: task, send_timeout: 10}

      assert :ok = AsyncWorker.terminate(:normal, state)
      assert_called_once(:brod.produce(_client_id, ^topic, 0, _key, ^remaining_messages))
    end

    test "any brod errors are logged before terminate", %{state: state, topic: topic} do
      remaining_messages = BrodApi.generate_producer_message_list(topic, 10)
      state = %{state | queue: :queue.from_list(remaining_messages), send_timeout: :infinity}

      patch(:brod, :sync_produce_request, fn _ref, _timeout ->
        {:error, :timeout}
      end)

      logs =
        capture_log(fn ->
          assert :ok = AsyncWorker.terminate(:normal, state)
        end)

      assert logs =~ "send 10 messages to Kafka before terminate"
      assert logs =~ "Error when sending messages to Kafka before termination"
      assert 11 = logs |> String.split("Unsent Kafka message") |> length()
    end

    test "any raised errors are logged before terminate", %{state: state, topic: topic} do
      remaining_messages = BrodApi.generate_producer_message_list(topic, 10)
      state = %{state | queue: :queue.from_list(remaining_messages), send_timeout: :infinity}

      patch(:brod, :sync_produce_request, fn _ref, _timeout ->
        raise RuntimeError, message: "test"
      end)

      logs =
        capture_log(fn ->
          assert :ok = AsyncWorker.terminate(:normal, state)
        end)

      assert logs =~ "send 10 messages to Kafka before terminate"
      assert logs =~ "exception was raised trying to send the remaining messages to Kafka"
      assert 11 = logs |> String.split("Unsent Kafka message") |> length()
    end
  end

  describe "build_message_batch/1" do
    test "allows configurable max request size" do
      messages = "topic" |> BrodApi.generate_producer_message_list(10_000) |> :queue.from_list()
      expose(AsyncWorker, build_message_batch: 2)

      batch = private(AsyncWorker.build_message_batch(messages, 1000))
      assert 6 = length(batch)
    end

    test "returns a list of messages under the max batch size" do
      messages = "topic" |> BrodApi.generate_producer_message_list(10_000) |> :queue.from_list()
      expose(AsyncWorker, build_message_batch: 2)

      batch = private(AsyncWorker.build_message_batch(messages, 1_040_384))
      assert 7029 = length(batch)

      {_batched_messages, remaining_messages} = :queue.split(length(batch), messages)
      remaining_batch = private(AsyncWorker.build_message_batch(remaining_messages, 1_040_384))
      assert 2971 = length(remaining_batch)

      assert 10_000 = length(batch) + length(remaining_batch)
    end

    test "always returns one message if the queue exists" do
      messages = "topic" |> BrodApi.generate_producer_message_list(10) |> :queue.from_list()
      expose(AsyncWorker, build_message_batch: 2)

      batch = private(AsyncWorker.build_message_batch(messages, 1))
      assert 1 = length(batch)
    end
  end

  if Version.match?(System.version(), ">= 1.14.0") do
    defp make_fake_task do
      %Task{
        ref: make_ref(),
        pid: self(),
        owner: self(),
        mfa: nil
      }
    end
  else
    defp make_fake_task do
      %Task{
        ref: make_ref(),
        pid: self(),
        owner: self()
      }
    end
  end
end
