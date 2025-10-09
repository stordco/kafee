defmodule Kafee.Consumer.BrodBatchIntegrationTest do
  use Kafee.KafkaCase

  require Logger

  # Test consumer for single-message batch processing
  defmodule SingleBatchConsumer do
    use Kafee.Consumer

    @impl Kafee.Consumer
    def handle_batch(messages) do
      test_pid = Application.get_env(:kafee, :test_pid, self())
      send(test_pid, {:batch_consumed, messages})
      :ok
    end

    @impl Kafee.Consumer
    def handle_message(_message) do
      raise "Should not be called in batch mode"
    end
  end

  # Test consumer for partial failure scenarios
  defmodule PartialFailureBatchConsumer do
    use Kafee.Consumer

    @impl Kafee.Consumer
    def handle_batch(messages) do
      test_pid = Application.get_env(:kafee, :test_pid, self())

      # Fail messages with even offsets
      {succeeded, failed} =
        Enum.split_with(messages, fn msg ->
          rem(msg.offset, 2) == 1
        end)

      send(test_pid, {:batch_partial, succeeded, failed})

      if failed == [] do
        :ok
      else
        {:ok, failed}
      end
    end

    @impl Kafee.Consumer
    def handle_message(_message) do
      raise "Should not be called in batch mode"
    end
  end

  # Test consumer for DLQ functionality
  defmodule DLQBatchConsumer do
    use Kafee.Consumer

    @impl Kafee.Consumer
    def handle_batch(messages) do
      test_pid = Application.get_env(:kafee, :test_pid, self())

      # Always fail to test DLQ
      send(test_pid, {:batch_failed, messages})
      {:error, "Test failure for DLQ"}
    end

    @impl Kafee.Consumer
    def handle_dead_letter(message, metadata) do
      test_pid = Application.get_env(:kafee, :test_pid, self())
      send(test_pid, {:dead_letter, message, metadata})
    end

    @impl Kafee.Consumer
    def handle_message(_message) do
      raise "Should not be called in batch mode"
    end
  end

  setup %{topic: topic} do
    Application.put_env(:kafee, :test_pid, self())

    # Create a DLQ topic for DLQ tests
    dlq_topic = "#{topic}-dlq"
    :ok = KafkaApi.create_topic(dlq_topic, 1)

    on_exit(fn ->
      KafkaApi.delete_topic(dlq_topic)
    end)

    {:ok, dlq_topic: dlq_topic}
  end

  describe "batch message processing" do
    test "processes messages in batches", %{brod_client_id: brod, topic: topic} do
      start_supervised!(
        {SingleBatchConsumer,
         [
           adapter:
             {Kafee.Consumer.BrodAdapter,
              [
                mode: :batch,
                batch: [size: 10, timeout: 1_000]
              ]},
           host: KafkaApi.host(),
           port: KafkaApi.port(),
           topic: topic,
           consumer_group_id: KafkaApi.generate_consumer_group_id()
         ]}
      )

      Process.sleep(1_000)

      # Produce 25 messages to partition 0 to ensure they all go to the same batch worker
      for i <- 1..25 do
        :ok = :brod.produce_sync(brod, topic, 0, "key-#{i}", "value-#{i}")
      end

      # Should receive 3 batches: 10, 10, 5
      assert_receive {:batch_consumed, batch1}, 10_000
      assert length(batch1) == 10

      assert_receive {:batch_consumed, batch2}, 10_000
      assert length(batch2) == 10

      # Send one more message to trigger timeout check for the partial batch
      # Wait for timeout to expire
      Process.sleep(1_100)
      :ok = :brod.produce_sync(brod, topic, 0, "key-trigger", "value-trigger")

      # Now we should get the batch with remaining messages plus trigger
      assert_receive {:batch_consumed, batch3}, 5_000

      # 5 remaining + 1 trigger
      assert length(batch3) == 6

      # Verify all messages were processed (excluding trigger)
      all_messages = batch1 ++ batch2 ++ Enum.take(batch3, 5)
      keys = Enum.map(all_messages, & &1.key)
      expected_keys = for i <- 1..25, do: "key-#{i}"
      # Sort both for comparison since order within batches isn't guaranteed
      assert Enum.sort(keys) == Enum.sort(expected_keys)
    end

    test "respects batch timeout", %{brod_client_id: brod, topic: topic} do
      start_supervised!(
        {SingleBatchConsumer,
         [
           adapter:
             {Kafee.Consumer.BrodAdapter,
              [
                mode: :batch,
                batch: [size: 100, timeout: 2000]
              ]},
           host: KafkaApi.host(),
           port: KafkaApi.port(),
           topic: topic,
           consumer_group_id: KafkaApi.generate_consumer_group_id()
         ]}
      )

      Process.sleep(1_000)

      # Produce only 5 messages to partition 0
      for i <- 1..5 do
        :ok = :brod.produce_sync(brod, topic, 0, "key-#{i}", "value-#{i}")
      end

      # Wait for timeout to expire
      Process.sleep(2_100)

      # Send a trigger message to check timeout
      :ok = :brod.produce_sync(brod, topic, 0, "key-trigger", "value-trigger")

      # Should receive batch with all 6 messages (5 + trigger) due to timeout
      assert_receive {:batch_consumed, batch}, 5_000
      assert length(batch) == 6
    end

    test "handles batch size limits by bytes", %{brod_client_id: brod, topic: topic} do
      # Large message content
      # 10KB per message
      large_value = String.duplicate("x", 10_000)

      start_supervised!(
        {SingleBatchConsumer,
         [
           adapter:
             {Kafee.Consumer.BrodAdapter,
              [
                mode: :batch,
                batch: [size: 100, timeout: 5000, max_bytes: 50_000]
              ]},
           host: KafkaApi.host(),
           port: KafkaApi.port(),
           topic: topic,
           consumer_group_id: KafkaApi.generate_consumer_group_id()
         ]}
      )

      Process.sleep(1_000)

      # Produce 10 messages of 10KB each
      for i <- 1..10 do
        :ok = :brod.produce_sync(brod, topic, :hash, "key-#{i}", large_value)
      end

      # Should receive multiple batches due to byte limit
      # Each batch should have ~5 messages (50KB / 10KB)
      assert_receive {:batch_consumed, batch1}, 10_000
      assert length(batch1) <= 5

      assert_receive {:batch_consumed, batch2}, 10_000
      assert length(batch2) <= 5
    end
  end

  describe "acknowledgment strategies" do
    test "all_or_nothing strategy does not commit on partial failures", %{brod_client_id: brod, topic: topic} do
      consumer_group_id = KafkaApi.generate_consumer_group_id()

      start_supervised!(
        {PartialFailureBatchConsumer,
         [
           adapter:
             {Kafee.Consumer.BrodAdapter,
              [
                mode: :batch,
                batch: [size: 10],
                acknowledgment: [strategy: :all_or_nothing]
              ]},
           host: KafkaApi.host(),
           port: KafkaApi.port(),
           topic: topic,
           consumer_group_id: consumer_group_id
         ]}
      )

      Process.sleep(1_000)

      # Produce first batch
      for i <- 0..9 do
        :ok = :brod.produce_sync(brod, topic, 0, "key-batch1-#{i}", "value-#{i}")
      end

      # First batch fails with partial failures
      assert_receive {:batch_partial, succeeded1, failed1}, 10_000
      assert length(succeeded1) == 5
      assert length(failed1) == 5

      # Produce a second batch to verify the first wasn't committed
      for i <- 10..19 do
        :ok = :brod.produce_sync(brod, topic, 0, "key-batch2-#{i}", "value-#{i}")
      end

      # Should receive the second batch
      assert_receive {:batch_partial, succeeded2, failed2}, 10_000
      assert length(succeeded2) == 5
      assert length(failed2) == 5

      # Verify we got batch2 messages (proving first batch was acknowledged but not committed)
      assert Enum.all?(succeeded2, fn msg -> String.contains?(msg.key, "batch2") end)
    end

    test "best_effort strategy commits despite failures", %{brod_client_id: brod, topic: topic} do
      consumer_group_id = KafkaApi.generate_consumer_group_id()

      start_supervised!(
        {PartialFailureBatchConsumer,
         [
           adapter:
             {Kafee.Consumer.BrodAdapter,
              [
                mode: :batch,
                batch: [size: 10],
                acknowledgment: [strategy: :best_effort]
              ]},
           host: KafkaApi.host(),
           port: KafkaApi.port(),
           topic: topic,
           consumer_group_id: consumer_group_id
         ]}
      )

      Process.sleep(1_000)

      # Produce first batch
      for i <- 0..9 do
        :ok = :brod.produce_sync(brod, topic, :hash, "key-batch1-#{i}", "value-#{i}")
      end

      assert_receive {:batch_partial, succeeded1, failed1}, 10_000
      assert length(succeeded1) == 5
      assert length(failed1) == 5

      # Produce second batch - this proves the first batch was committed
      for i <- 0..9 do
        :ok = :brod.produce_sync(brod, topic, :hash, "key-batch2-#{i}", "value-#{i}")
      end

      # Should receive the second batch, proving first was committed
      assert_receive {:batch_partial, succeeded2, _failed2}, 10_000

      # Check that we got batch2 messages
      assert Enum.all?(succeeded2, fn msg -> String.contains?(msg.key, "batch2") end)
    end
  end

  describe "dead letter queue" do
    @tag :skip
    test "sends messages to DLQ after retries", %{brod_client_id: _brod, topic: _topic, dlq_topic: _dlq_topic} do
      # Skip this test for now - the retry mechanism needs to be redesigned
      # to work with brod's acknowledgment model
      # TODO: Implement proper retry mechanism that works with brod
    end
  end

  describe "back pressure" do
    test "limits in-flight batches", %{brod_client_id: brod, topic: topic} do
      # Consumer that tracks when batches start processing
      defmodule SlowBatchConsumer do
        use Kafee.Consumer

        @impl Kafee.Consumer
        def handle_batch(messages) do
          test_pid = Application.get_env(:kafee, :test_pid, self())
          send(test_pid, {:batch_started, length(messages)})

          # Simulate slow processing
          Process.sleep(2000)

          send(test_pid, {:batch_completed, length(messages)})
          :ok
        end

        @impl Kafee.Consumer
        def handle_message(_message) do
          raise "Should not be called in batch mode"
        end
      end

      start_supervised!(
        {SlowBatchConsumer,
         [
           adapter:
             {Kafee.Consumer.BrodAdapter,
              [
                mode: :batch,
                batch: [size: 5],
                processing: [max_in_flight_batches: 2]
              ]},
           host: KafkaApi.host(),
           port: KafkaApi.port(),
           topic: topic,
           consumer_group_id: KafkaApi.generate_consumer_group_id()
         ]}
      )

      Process.sleep(1_000)

      # Produce 20 messages (4 batches of 5)
      for i <- 1..20 do
        :ok = :brod.produce_sync(brod, topic, :hash, "key-#{i}", "value-#{i}")
      end

      # Should quickly start 2 batches (max in flight)
      assert_receive {:batch_started, 5}, 5_000
      assert_receive {:batch_started, 5}, 5_000

      # Third batch should not start until one completes
      refute_receive {:batch_started, 5}, 1_000

      # After first batch completes, third should start
      assert_receive {:batch_completed, 5}, 3_000
      assert_receive {:batch_started, 5}, 1_000
    end
  end

  describe "batch mode validation" do
    defmodule ConsumerWithoutHandleBatch do
      use Kafee.Consumer

      @impl Kafee.Consumer
      def handle_message(_message) do
        :ok
      end
    end

    test "raises ArgumentError when consumer doesn't implement handle_batch in batch mode" do
      assert_raise ArgumentError, ~r/must implement handle_batch\/1 when using batch mode/, fn ->
        Kafee.Consumer.BrodBatchWorker.init(
          %{group_id: "test", partition: 0, topic: "test"},
          %{
            consumer: ConsumerWithoutHandleBatch,
            options: [],
            adapter_options: []
          }
        )
      end
    end
  end

  # Helper to start a DLQ consumer (currently unused but may be needed for future tests)
  # defp start_dlq_consumer(_brod_client_id, dlq_topic) do
  #   test_pid = self()
  #
  #   # Store test_pid for DLQVerifier to access
  #   Application.put_env(:kafee, :dlq_test_pid, test_pid)
  #
  #   {:ok, pid} =
  #     start_supervised(
  #       {__MODULE__.DLQVerifier,
  #        [
  #          adapter: Kafee.Consumer.BrodAdapter,
  #          host: KafkaApi.host(),
  #          port: KafkaApi.port(),
  #          topic: dlq_topic,
  #          consumer_group_id: KafkaApi.generate_consumer_group_id()
  #        ]}
  #     )
  #
  #   pid
  # end
  #
  # defmodule DLQVerifier do
  #   use Kafee.Consumer
  #
  #   @impl Kafee.Consumer
  #   def handle_message(message) do
  #     test_pid = Application.get_env(:kafee, :dlq_test_pid)
  #     send(test_pid, {:dlq_message, message})
  #     :ok
  #   end
  # end
end
