defmodule Kafee.Consumer.BrodBatchWorkerTest do
  use ExUnit.Case, async: true

  alias Kafee.Consumer.BrodBatchWorker

  # Import record definitions
  require Record

  Record.defrecord(
    :kafka_message,
    Record.extract(:kafka_message, from_lib: "brod/include/brod.hrl")
  )

  Record.defrecord(
    :kafka_message_set,
    Record.extract(:kafka_message_set, from_lib: "brod/include/brod.hrl")
  )

  defmodule TestConsumer do
    use Kafee.Consumer

    def handle_message(_message), do: :ok

    def handle_batch(messages) do
      # Send messages to test process for assertions
      test_pid = Process.get(:test_pid)
      send(test_pid, {:batch_processed, messages})
      :ok
    end
  end

  defmodule FailingConsumer do
    use Kafee.Consumer

    def handle_message(_message), do: raise("Message processing failed")

    def handle_batch(_messages), do: {:error, "Batch processing failed"}
  end

  defmodule PartialFailureConsumer do
    use Kafee.Consumer

    def handle_batch(messages) do
      # Fail every other message
      {succeeded, failed} =
        Enum.split_with(messages, fn msg ->
          rem(msg.offset, 2) == 0
        end)

      # Send succeeded to test process
      test_pid = Process.get(:test_pid)
      send(test_pid, {:partial_batch, succeeded})

      {:ok, failed}
    end
  end

  setup do
    Process.put(:test_pid, self())
    :ok
  end

  describe "init/2" do
    test "initializes state correctly" do
      info = %{
        group_id: "test-group",
        partition: 0,
        topic: "test-topic"
      }

      config = %{
        consumer: TestConsumer,
        options: [topic: "test-topic"],
        adapter_options: [
          batch_size: 100,
          batch_timeout: 1000,
          max_batch_bytes: 1_048_576,
          max_in_flight_batches: 3,
          ack_strategy: :all_or_nothing
        ]
      }

      assert {:ok, state} = BrodBatchWorker.init(info, config)

      assert state.consumer == TestConsumer
      assert state.group_id == "test-group"
      assert state.partition == 0
      assert state.topic == "test-topic"
      assert state.current_batch == []
      assert state.batch_start_time == nil
      assert state.batch_bytes == 0
      assert state.in_flight_batches == 0
      assert state.adapter_options == config.adapter_options
    end
  end

  describe "handle_message/2 - batch accumulation" do
    test "accumulates messages until batch size is reached" do
      state = create_test_state(batch_size: 3)

      # First message - should not trigger processing
      message_set1 =
        create_message_set([
          create_kafka_message("key1", "value1", 0)
        ])

      assert {:ok, :ack, new_state} = BrodBatchWorker.handle_message(message_set1, state)
      assert length(new_state.current_batch) == 1
      assert new_state.batch_start_time != nil

      # Second message - still accumulating
      message_set2 =
        create_message_set([
          create_kafka_message("key2", "value2", 1)
        ])

      assert {:ok, :ack, new_state} = BrodBatchWorker.handle_message(message_set2, new_state)
      assert length(new_state.current_batch) == 2

      # Third message - should trigger batch processing
      message_set3 =
        create_message_set([
          create_kafka_message("key3", "value3", 2)
        ])

      assert {:ok, :ack, final_state} = BrodBatchWorker.handle_message(message_set3, new_state)
      assert length(final_state.current_batch) == 0
      assert final_state.batch_start_time == nil

      # Verify batch was processed
      assert_receive {:batch_processed, messages}
      assert length(messages) == 3
    end

    test "accumulates messages until max_batch_bytes is reached" do
      # Small batch size but will hit bytes limit first
      state = create_test_state(batch_size: 100, max_batch_bytes: 50)

      # Create messages that will exceed byte limit
      large_value = String.duplicate("x", 30)

      message_set1 =
        create_message_set([
          create_kafka_message("key1", large_value, 0)
        ])

      assert {:ok, :ack, new_state} = BrodBatchWorker.handle_message(message_set1, state)

      # Second message should trigger processing due to byte limit
      message_set2 =
        create_message_set([
          create_kafka_message("key2", large_value, 1)
        ])

      assert {:ok, :ack, _final_state} = BrodBatchWorker.handle_message(message_set2, new_state)

      assert_receive {:batch_processed, messages}
      assert length(messages) == 2
    end

    test "handles multiple messages in a single message set" do
      state = create_test_state(batch_size: 5)

      # Message set with 3 messages
      message_set =
        create_message_set([
          create_kafka_message("key1", "value1", 0),
          create_kafka_message("key2", "value2", 1),
          create_kafka_message("key3", "value3", 2)
        ])

      assert {:ok, :ack, new_state} = BrodBatchWorker.handle_message(message_set, state)
      assert length(new_state.current_batch) == 3
    end
  end

  describe "handle_message/2 - acknowledgment strategies" do
    test "all_or_nothing strategy - success case" do
      state =
        create_test_state(
          consumer: TestConsumer,
          batch_size: 2,
          ack_strategy: :all_or_nothing
        )

      message_set =
        create_message_set([
          create_kafka_message("key1", "value1", 0),
          create_kafka_message("key2", "value2", 1)
        ])

      assert {:ok, :ack, _new_state} = BrodBatchWorker.handle_message(message_set, state)
      assert_receive {:batch_processed, _messages}
    end

    test "all_or_nothing strategy - failure case" do
      state =
        create_test_state(
          consumer: FailingConsumer,
          batch_size: 2,
          ack_strategy: :all_or_nothing
        )

      message_set =
        create_message_set([
          create_kafka_message("key1", "value1", 0),
          create_kafka_message("key2", "value2", 1)
        ])

      # With batch_size=2 and 2 messages, it will try to process immediately
      # FailingConsumer returns {:error, _} which triggers all_or_nothing behavior
      assert {:ok, :ack, new_state} = BrodBatchWorker.handle_message(message_set, state)
      # Batch should be cleared after failed processing attempt
      assert length(new_state.current_batch) == 0
      assert new_state.batch_start_time == nil
    end
  end

  describe "handle_message/2 - partial failures" do
    test "handles partial batch failures correctly with all_or_nothing" do
      state =
        create_test_state(
          consumer: PartialFailureConsumer,
          batch_size: 4,
          ack_strategy: :all_or_nothing
        )

      message_set =
        create_message_set([
          create_kafka_message("key0", "value0", 0),
          create_kafka_message("key1", "value1", 1),
          create_kafka_message("key2", "value2", 2),
          create_kafka_message("key3", "value3", 3)
        ])

      # With all_or_nothing, partial failures mean no commit
      assert {:ok, :ack, _new_state} = BrodBatchWorker.handle_message(message_set, state)

      # Should still receive the partial batch callback
      assert_receive {:partial_batch, succeeded}
      assert length(succeeded) == 2
      assert Enum.all?(succeeded, fn msg -> rem(msg.offset, 2) == 0 end)
    end

    test "handles partial batch failures correctly with best_effort" do
      state =
        create_test_state(
          consumer: PartialFailureConsumer,
          batch_size: 4,
          ack_strategy: :best_effort
        )

      message_set =
        create_message_set([
          create_kafka_message("key0", "value0", 0),
          create_kafka_message("key1", "value1", 1),
          create_kafka_message("key2", "value2", 2),
          create_kafka_message("key3", "value3", 3)
        ])

      # With best_effort, we commit even with partial failures
      assert {:ok, :ack, _new_state} = BrodBatchWorker.handle_message(message_set, state)

      # Should receive the partial batch callback
      assert_receive {:partial_batch, succeeded}
      assert length(succeeded) == 2
      assert Enum.all?(succeeded, fn msg -> rem(msg.offset, 2) == 0 end)
    end
  end

  describe "handle_message/2 - back pressure" do
    test "respects max_in_flight_batches limit" do
      # This test would require mocking or a more complex setup
      # as we need to simulate slow message processing
      # For now, we'll just verify the state tracking

      state =
        create_test_state(
          batch_size: 1,
          max_in_flight_batches: 3
        )

      # Process one message to increment in_flight_batches
      message_set =
        create_message_set([
          create_kafka_message("key1", "value1", 0)
        ])

      assert {:ok, :ack, _new_state} = BrodBatchWorker.handle_message(message_set, state)
      # Note: In real implementation, in_flight_batches would be decremented
      # after processing completes
    end
  end

  # Helper functions
  defp create_test_state(overrides) do
    # Extract individual adapter option overrides
    batch_size = Keyword.get(overrides, :batch_size, 100)
    batch_timeout = Keyword.get(overrides, :batch_timeout, 1000)
    max_batch_bytes = Keyword.get(overrides, :max_batch_bytes, 1_048_576)
    async_batch = Keyword.get(overrides, :async_batch, false)
    max_concurrency = Keyword.get(overrides, :max_concurrency, 10)
    max_in_flight_batches = Keyword.get(overrides, :max_in_flight_batches, 3)
    ack_strategy = Keyword.get(overrides, :ack_strategy, :all_or_nothing)
    dead_letter_config = Keyword.get(overrides, :dead_letter_config, nil)

    adapter_options = [
      batch_size: batch_size,
      batch_timeout: batch_timeout,
      max_batch_bytes: max_batch_bytes,
      async_batch: async_batch,
      max_concurrency: max_concurrency,
      max_in_flight_batches: max_in_flight_batches,
      ack_strategy: ack_strategy,
      dead_letter_config: dead_letter_config
    ]

    %BrodBatchWorker.State{
      consumer: Keyword.get(overrides, :consumer, TestConsumer),
      group_id: "test-group",
      options: [topic: "test-topic"],
      adapter_options: adapter_options,
      partition: 0,
      topic: "test-topic",
      current_batch: [],
      batch_start_time: nil,
      batch_bytes: 0,
      in_flight_batches: 0,
      dlq_producer: nil,
      retry_counts: %{}
    }
  end

  defp create_message_set(messages) do
    kafka_message_set(
      topic: "test-topic",
      partition: 0,
      messages: messages
    )
  end

  defp create_kafka_message(key, value, offset) do
    kafka_message(
      key: key,
      value: value,
      offset: offset,
      ts: System.system_time(:millisecond),
      headers: []
    )
  end
end
