defmodule Kafee.Producer.AsyncWorkerTest do
  # It's worth mentioning that some of the tests in this file deal with
  # binary size batching and are very flaky due to different OTP versions
  # and how data is stored low level. Most of those tests test against a
  # wide range to still assert what we need, but avoid flake.

  use Kafee.KafkaCase

  import ExUnit.CaptureLog

  alias Kafee.Producer.AsyncWorker

  # Generally enough time for the worker to do what ever it needs to do.
  @wait_timeout 500

  setup do
    spy(:brod)
    on_exit(fn -> restore(:brod) end)

    spy(Datadog.DataStreams.Integrations.Kafka)
    on_exit(fn -> restore(Datadog.DataStreams.Integrations.Kafka) end)

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
           max_request_bytes: 1_040_384,
           partition: 0,
           send_timeout: :timer.seconds(10),
           throttle_ms: 1,
           topic: topic
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
      brod_messages = BrodApi.to_kafka_message(messages)

      state = %{state | queue: :queue.from_list(messages)}

      assert {:noreply, new_state} = AsyncWorker.handle_info(:send, state)
      refute is_nil(new_state.send_task)

      Process.sleep(@wait_timeout)

      assert_called_once(:brod.produce(_client_id, ^topic, 0, _key, ^brod_messages))
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

      assert {:noreply, new_state} = AsyncWorker.handle_info({task.ref, {:ok, 4, 0}}, state)
      assert ^remaining_messages = :queue.to_list(new_state.queue)
    end

    test ":ok emits telemetry of remaining messages", %{state: state, topic: topic} do
      task = make_fake_task()
      send_messages = BrodApi.generate_producer_message_list(topic, 4)
      remaining_messages = BrodApi.generate_producer_message_list(topic, 3)
      state = %{state | send_task: task, queue: :queue.from_list(send_messages ++ remaining_messages)}

      assert {:noreply, _new_state} = AsyncWorker.handle_info({task.ref, {:ok, 4, 0}}, state)
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
      large_message = String.duplicate(message_fixture, 10)

      message =
        topic
        |> BrodApi.generate_producer_message()
        |> Map.put(:value, large_message)

      log =
        capture_log(fn ->
          assert :ok = AsyncWorker.queue(pid, [message])
          Process.sleep(@wait_timeout)
        end)

      brod_message = BrodApi.to_kafka_message(message)
      assert_called(:brod.produce(_client_id, ^topic, 0, :undefined, [^brod_message]))
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
      remaining_brod_messages = BrodApi.to_kafka_message(remaining_messages)

      state = %{state | queue: :queue.from_list(remaining_messages)}

      assert :ok = AsyncWorker.terminate(:normal, state)
      assert_called_once(:brod.produce(_client_id, ^topic, 0, _key, ^remaining_brod_messages))
    end

    test "waits for in flight send and sends remaining messages", %{state: state, topic: topic} do
      remaining_messages = BrodApi.generate_producer_message_list(topic, 20)
      remaining_brod_messages = BrodApi.to_kafka_message(remaining_messages)

      task = make_fake_task()
      state = %{state | queue: :queue.from_list(remaining_messages), send_task: task, send_timeout: :infinity}

      Process.send_after(self(), {task.ref, {:ok, 0, 0}}, 10)
      assert :ok = AsyncWorker.terminate(:normal, state)
      assert_called_once(:brod.produce(_client_id, ^topic, 0, _key, ^remaining_brod_messages))
    end

    @tag capture_log: true
    test "waits for in flight error and retries sending messages", %{state: state, topic: topic} do
      remaining_messages = BrodApi.generate_producer_message_list(topic, 20)
      remaining_brod_messages = BrodApi.to_kafka_message(remaining_messages)

      task = make_fake_task()
      state = %{state | queue: :queue.from_list(remaining_messages), send_task: task, send_timeout: :infinity}

      Process.send_after(self(), {task.ref, {:error, :internal_error}}, 10)
      assert :ok = AsyncWorker.terminate(:normal, state)
      assert_called_once(:brod.produce(_client_id, ^topic, 0, _key, ^remaining_brod_messages))
    end

    test "waits for timeout and retries sending messages", %{state: state, topic: topic} do
      remaining_messages = BrodApi.generate_producer_message_list(topic, 20)
      remaining_brod_messages = BrodApi.to_kafka_message(remaining_messages)

      task = make_fake_task()
      state = %{state | queue: :queue.from_list(remaining_messages), send_task: task, send_timeout: 10}

      assert :ok = AsyncWorker.terminate(:normal, state)
      assert_called_once(:brod.produce(_client_id, ^topic, 0, _key, ^remaining_brod_messages))
    end

    test "any brod errors are logged before terminate", %{state: state, topic: topic} do
      remaining_messages = BrodApi.generate_producer_message_list(topic, 10)
      state = %{state | queue: :queue.from_list(remaining_messages), send_timeout: :infinity}

      patch(:brod, :sync_produce_request_offset, fn _ref, _timeout ->
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

      patch(:brod, :sync_produce_request_offset, fn _ref, _timeout ->
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

    @tag capture_log: true
    test "any leftover messages that are large during shutdown gets logged and will not publish", %{
      pid: pid,
      topic: topic,
      state: state
    } do
      [small_message_1, small_message_2] = BrodApi.generate_producer_message_list(topic, 2)
      message_fixture = File.read!("test/support/example/large_message.json")
      large_message_fixture = String.duplicate(message_fixture, 10)

      # This message will skip being sent to Kafka, and only be logged
      large_message_1 =
        topic
        |> BrodApi.generate_producer_message()
        |> Map.put(:value, large_message_fixture)
        |> Map.put(:key, "large_msg_1")

      remaining_messages = [small_message_1, large_message_1, small_message_2]
      state = %{state | queue: :queue.from_list(remaining_messages), send_timeout: :infinity}

      log =
        capture_log(fn ->
          assert :ok = AsyncWorker.terminate(:normal, state)
          Process.sleep(@wait_timeout)
        end)

      remaining_brod_messages = BrodApi.to_kafka_message([small_message_1, small_message_2])
      assert_called_once(:brod.produce(_client_id, ^topic, 0, _key, ^remaining_brod_messages))

      async_worker_state = pid |> Patch.Listener.target() |> :sys.get_state()
      assert 0 == :queue.len(async_worker_state.queue)

      assert log =~ "Message in queue is too large, will not push to Kafka"
      assert log =~ "send 2 messages to Kafka before terminate"
      refute log =~ "exception was raised trying to send the remaining messages to Kafka"
      refute log =~ "Unsent Kafka message"
    end

    @tag capture_log: true
    test "should handle leftover messages which are each small sized but have a total size exceeds max_request_bytes",
         %{
           pid: pid,
           topic: topic,
           state: %{max_request_bytes: max_request_bytes} = state
         } do
      [small_message] = BrodApi.generate_producer_message_list(topic, 1)
      small_message_unit_size = kafka_message_size_bytes(small_message)

      small_message_total = Kernel.ceil(max_request_bytes / small_message_unit_size)
      remaining_messages = BrodApi.generate_producer_message_list(topic, small_message_total)

      state = %{state | queue: :queue.from_list(remaining_messages), send_timeout: :infinity}

      log =
        capture_log(fn ->
          assert :ok = AsyncWorker.terminate(:normal, state)
          Process.sleep(@wait_timeout)
        end)

      # just asswert if called; lower level :brod code might split up the messages into more then one call
      assert_called(:brod.produce(_client_id, ^topic, 0, _key, _messages))

      async_worker_state = pid |> Patch.Listener.target() |> :sys.get_state()
      assert 0 == :queue.len(async_worker_state.queue)

      assert log =~ "send #{small_message_total} messages to Kafka before terminate"
      refute log =~ "exception was raised trying to send the remaining messages to Kafka"
      refute log =~ "Unsent Kafka message"
    end
  end

  describe "build_message_batch/1" do
    test "allows configurable max request size" do
      messages = "topic" |> BrodApi.generate_producer_message_list(10_000) |> :queue.from_list()
      expose(AsyncWorker, build_message_batch: 2)

      batch = private(AsyncWorker.build_message_batch(messages, 1_000))
      # This is not an exact science.
      assert length(batch) in 4..20
    end

    test "returns a list of messages under the max batch size" do
      messages = "topic" |> BrodApi.generate_producer_message_list(20_000) |> :queue.from_list()
      expose(AsyncWorker, build_message_batch: 2)

      batch = private(AsyncWorker.build_message_batch(messages, 1_040_384))
      assert length(batch) in 10_000..15_000

      {_batched_messages, remaining_messages} = batch |> length() |> :queue.split(messages)
      remaining_batch = private(AsyncWorker.build_message_batch(remaining_messages, 1_040_384))
      assert length(remaining_batch) in 5_000..10_000

      assert 20_000 = length(batch) + length(remaining_batch)
    end

    test "always returns one message if the queue exists" do
      messages = "topic" |> BrodApi.generate_producer_message_list(10) |> :queue.from_list()
      expose(AsyncWorker, build_message_batch: 2)

      batch = private(AsyncWorker.build_message_batch(messages, 1))
      assert 1 = length(batch)
    end
  end

  describe "Datadog.DataStreams.Integrations.Kafka" do
    test "calls track_produce/3 with current produce offset", %{pid: pid, topic: topic} do
      # We send the first message to ensure the offset gets set to something not 0. This
      # isn't strictly required, but it's nice to test that the offset number isn't just
      # being ignored or unset.
      first_message = BrodApi.generate_producer_message(topic)
      assert :ok = AsyncWorker.queue(pid, [first_message])
      Process.sleep(@wait_timeout)

      # Then we finally send the actual messages
      more_messages = BrodApi.generate_producer_message_list(topic, 20)
      assert :ok = AsyncWorker.queue(pid, more_messages)
      Process.sleep(@wait_timeout)

      # Now we can assert that the actual call was made and that the offset was not 0
      # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
      assert_called(Datadog.DataStreams.Integrations.Kafka.track_produce(^topic, 0, offset))
      assert offset >= 1
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

  defp kafka_message_size_bytes(message) do
    message
    |> Map.take([:key, :value, :headers])
    |> :erlang.external_size()
  end
end
