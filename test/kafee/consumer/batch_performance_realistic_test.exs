defmodule Kafee.Consumer.BatchPerformanceRealisticTest do
  use Kafee.KafkaCase

  require Logger

  # Simulates a consumer that makes database calls
  defmodule DatabaseConsumer do
    use Kafee.Consumer

    @impl Kafee.Consumer
    def handle_message(message) do
      # Simulate database insert (network I/O)
      # 5ms per message = realistic DB latency
      Process.sleep(5)

      # Simulate JSON parsing
      Jason.decode!(message.value)

      test_pid = Application.get_env(:kafee, :test_pid)
      send(test_pid, {:message_processed, 1})
      :ok
    end
  end

  # Simulates batch database operations
  defmodule BatchDatabaseConsumer do
    use Kafee.Consumer

    @impl Kafee.Consumer
    def handle_batch(messages) do
      # Simulate bulk database insert
      # Batch of 50 takes only 10ms vs 250ms for individual inserts!
      Process.sleep(10)

      # Parse all messages
      Enum.each(messages, fn msg ->
        Jason.decode!(msg.value)
      end)

      test_pid = Application.get_env(:kafee, :test_pid)
      send(test_pid, {:message_processed, length(messages)})
      :ok
    end

    @impl Kafee.Consumer
    def handle_message(_message) do
      raise "Should not be called in batch mode"
    end
  end

  setup do
    Application.put_env(:kafee, :test_pid, self())
    :ok
  end

  @tag :performance
  @tag timeout: 120_000
  test "realistic batch vs single message performance", %{topic: topic, brod_client_id: brod} do
    message_count = 200

    IO.puts("\n=== Realistic Batch Performance Test ===")
    IO.puts("Simulating database operations with #{message_count} messages")
    IO.puts("Single message: 5ms latency per INSERT")
    IO.puts("Batch: 10ms for entire batch INSERT\n")

    IO.puts("Testing single message processing (with DB latency)...")

    start_supervised!(
      {DatabaseConsumer,
       [
         adapter: Kafee.Consumer.BrodAdapter,
         host: KafkaApi.host(),
         port: KafkaApi.port(),
         topic: topic,
         consumer_group_id: KafkaApi.generate_consumer_group_id()
       ]}
    )

    Process.sleep(5_000)

    single_start = System.monotonic_time(:millisecond)

    # Produce messages
    for i <- 1..message_count do
      :ok =
        :brod.produce_sync(
          brod,
          topic,
          0,
          "key-#{i}",
          Jason.encode!(%{
            id: i,
            data: "test-#{i}",
            timestamp: System.system_time(),
            payload: String.duplicate("x", 100)
          })
        )
    end

    wait_for_messages(message_count)
    single_duration = System.monotonic_time(:millisecond) - single_start

    stop_supervised(DatabaseConsumer)

    single_throughput = message_count / (single_duration / 1000)
    # 5ms per message
    expected_single_time = message_count * 5

    IO.puts("Single Message Processing:")
    IO.puts("  Expected min duration: #{expected_single_time}ms (just DB operations)")
    IO.puts("  Actual duration: #{single_duration}ms")
    IO.puts("  Throughput: #{Float.round(single_throughput, 2)} msg/s\n")

    # Clear mailbox
    flush_messages()

    # Test batch processing
    batch_sizes = [10, 50]

    Enum.each(batch_sizes, fn batch_size ->
      IO.puts("Testing batch processing (size=#{batch_size})...")

      start_supervised!(
        {BatchDatabaseConsumer,
         [
           adapter:
             {Kafee.Consumer.BrodAdapter,
              [
                mode: :batch,
                batch: [size: batch_size, timeout: 1000]
              ]},
           host: KafkaApi.host(),
           port: KafkaApi.port(),
           topic: topic,
           consumer_group_id: KafkaApi.generate_consumer_group_id()
         ]}
      )

      Process.sleep(5_000)

      batch_start = System.monotonic_time(:millisecond)

      # Produce messages
      for i <- 1..message_count do
        :ok =
          :brod.produce_sync(
            brod,
            topic,
            0,
            "key-#{i}",
            Jason.encode!(%{
              id: i,
              data: "test-#{i}",
              timestamp: System.system_time(),
              payload: String.duplicate("x", 100)
            })
          )
      end

      wait_for_messages(message_count)
      batch_duration = System.monotonic_time(:millisecond) - batch_start

      stop_supervised(BatchDatabaseConsumer)

      batch_throughput = message_count / (batch_duration / 1000)
      # 10ms per batch
      expected_batch_time = div(message_count, batch_size) * 10
      speedup = single_duration / batch_duration

      IO.puts("Batch Processing (size=#{batch_size}):")
      IO.puts("  Expected min duration: #{expected_batch_time}ms (just DB operations)")
      IO.puts("  Actual duration: #{batch_duration}ms")
      IO.puts("  Throughput: #{Float.round(batch_throughput, 2)} msg/s")
      IO.puts("  Speedup: #{Float.round(speedup, 2)}x\n")

      # Clear mailbox
      flush_messages()
    end)

    IO.puts("💡 Key Insights:")
    IO.puts("- Single message: Each message requires a separate DB transaction")
    IO.puts("- Batch: Multiple messages share a single DB transaction")
    IO.puts("- Real-world batching can provide 10-50x improvements for I/O operations")
  end

  defp wait_for_messages(expected_count, processed \\ 0) do
    receive do
      {:message_processed, count} ->
        new_total = processed + count

        if new_total >= expected_count do
          :ok
        else
          wait_for_messages(expected_count, new_total)
        end
    after
      30_000 ->
        flunk("Timeout waiting for messages. Processed #{processed}/#{expected_count}")
    end
  end

  defp flush_messages do
    receive do
      {:message_processed, _} -> flush_messages()
    after
      0 -> :ok
    end
  end
end
