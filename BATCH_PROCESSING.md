# Batch Processing Guide for Kafee

This guide covers the batch processing capabilities added to Kafee's BrodAdapter, including configuration, usage patterns, and migration from single-message processing.

## Overview

Batch processing allows you to process multiple Kafka messages together, significantly improving throughput for high-volume scenarios. Instead of processing messages one at a time, you can accumulate messages and process them in batches.

## Configuration

### Basic Batch Configuration

```elixir
defmodule MyBatchConsumer do
  use Kafee.Consumer
  
  @impl Kafee.Consumer
  def handle_batch(messages) do
    # Process batch of messages
    :ok
  end
end

# In your supervisor
{MyBatchConsumer, [
  adapter: {Kafee.Consumer.BrodAdapter, [
    mode: :batch,
    batch: [
      size: 100,        # Process when batch reaches 100 messages
      timeout: 5000,    # Process after 5 seconds even if not full
      max_bytes: 1_048_576  # Process when batch reaches 1MB
    ]
  ]},
  host: "localhost",
  port: 9092,
  topic: "my-topic",
  consumer_group_id: "my-consumer-group"
]}
```

### Acknowledgment Strategies

Control how message acknowledgments work when some messages in a batch fail:

```elixir
adapter: {Kafee.Consumer.BrodAdapter, [
  mode: :batch,
  batch: [size: 100],
  acknowledgment: [
    strategy: :best_effort  # Options: :all_or_nothing, :best_effort, :last_successful
  ]
]}
```

- **`:all_or_nothing`** (default) - Only commit if all messages succeed. Failed batches are retried.
- **`:best_effort`** - Always commit, even with failures. Good for scenarios where some data loss is acceptable.
- **`:last_successful`** - Commit up to the last successful message. Ensures no data loss but may reprocess some messages.

### Back-Pressure Control

Limit how many batches can be processed concurrently:

```elixir
adapter: {Kafee.Consumer.BrodAdapter, [
  mode: :batch,
  batch: [size: 100],
  processing: [
    max_in_flight_batches: 3  # Only process 3 batches concurrently
  ]
]}
```

### Dead Letter Queue (DLQ)

Handle messages that repeatedly fail processing:

```elixir
# First, start a shared DLQ producer
{Kafee.DLQProducer, [
  name: :my_dlq_producer,
  host: "localhost",
  port: 9092,
  topic: "dead-letter-queue"
]}

# Then configure your consumer
adapter: {Kafee.Consumer.BrodAdapter, [
  mode: :batch,
  batch: [size: 100],
  acknowledgment: [
    strategy: :best_effort,
    dead_letter_producer: :my_dlq_producer,
    dead_letter_max_retries: 3
  ]
]}
```

## Implementing Batch Handlers

### Basic Batch Handler

```elixir
defmodule MyBatchConsumer do
  use Kafee.Consumer
  
  @impl Kafee.Consumer
  def handle_batch(messages) do
    # Process all messages
    results = Enum.map(messages, &process_message/1)
    
    # Return :ok if all succeeded
    if Enum.all?(results, &match?({:ok, _}, &1)) do
      :ok
    else
      # Return failed messages for retry/DLQ
      failed_messages = 
        Enum.zip(messages, results)
        |> Enum.filter(fn {_msg, result} -> !match?({:ok, _}, result) end)
        |> Enum.map(fn {msg, _result} -> msg end)
      
      {:ok, failed_messages}
    end
  end
  
  defp process_message(message) do
    # Your processing logic here
    {:ok, :processed}
  rescue
    error -> {:error, error}
  end
end
```

### Batch Handler with Database Operations

```elixir
defmodule BulkInsertConsumer do
  use Kafee.Consumer
  
  @impl Kafee.Consumer
  def handle_batch(messages) do
    # Parse all messages
    records = Enum.map(messages, &parse_message/1)
    
    # Bulk insert
    case MyApp.Repo.insert_all(MySchema, records) do
      {n, _} when n == length(records) ->
        :ok
        
      {n, _} ->
        # Some inserts failed - figure out which ones
        # This is application-specific logic
        {:error, "Only inserted #{n} of #{length(records)} records"}
    end
  end
end
```

### Handling Dead Letters

```elixir
defmodule MyBatchConsumer do
  use Kafee.Consumer
  
  @impl Kafee.Consumer
  def handle_batch(messages) do
    # ... batch processing logic ...
  end
  
  @impl Kafee.Consumer
  def handle_dead_letter(message, metadata) do
    # Log, alert, or store for manual review
    Logger.error("Message sent to DLQ", 
      message: message,
      retry_count: metadata.retry_count,
      dlq_topic: metadata.dlq_topic
    )
    
    # Could also write to a database, send alerts, etc.
  end
end
```

## Migration Guide

### From Single-Message to Batch Processing

1. **Update your consumer module:**

```elixir
defmodule MyConsumer do
  use Kafee.Consumer
  
  # Keep the single-message handler for compatibility
  @impl Kafee.Consumer
  def handle_message(message) do
    # Existing logic
  end
  
  # Add batch handler
  @impl Kafee.Consumer
  def handle_batch(messages) do
    # Option 1: Reuse existing logic
    results = Enum.map(messages, &handle_message/1)
    
    failed = Enum.filter(messages, fn msg ->
      handle_message(msg) != :ok
    end)
    
    case failed do
      [] -> :ok
      failed_messages -> {:ok, failed_messages}
    end
  end
end
```

2. **Update configuration:**

```elixir
# Change from:
{MyConsumer, [
  adapter: Kafee.Consumer.BrodAdapter,
  host: "localhost",
  port: 9092,
  topic: "my-topic",
  consumer_group_id: "my-group"
]}

# To:
{MyConsumer, [
  adapter: {Kafee.Consumer.BrodAdapter, [
    mode: :batch,
    batch: [size: 100, timeout: 5000]
  ]},
  host: "localhost",
  port: 9092,
  topic: "my-topic",
  consumer_group_id: "my-group"
]}
```

### Gradual Migration

You can run both single-message and batch consumers during migration:

```elixir
# Existing single-message consumer continues running
{MyConsumer, [
  adapter: Kafee.Consumer.BrodAdapter,
  # ... config
]}

# New batch consumer with different consumer group
{MyConsumer, [
  adapter: {Kafee.Consumer.BrodAdapter, [
    mode: :batch,
    batch: [size: 100]
  ]},
  consumer_group_id: "my-group-batch",  # Different group!
  # ... rest of config
]}
```

## Performance Tuning

### Batch Size

- **Small batches (10-50)**: Lower latency, more overhead
- **Medium batches (100-500)**: Good balance for most use cases  
- **Large batches (1000+)**: Maximum throughput, higher latency

### Timeout Settings

- Set timeout to your maximum acceptable latency
- Consider business requirements (e.g., real-time vs batch processing)
- Account for processing time in your timeout

### Memory Considerations

- Each batch holds messages in memory
- With `max_in_flight_batches: 3` and `batch_size: 1000`, you could have 3000 messages in memory
- Consider message size when setting limits

## Monitoring

Monitor these metrics (see TELEMETRY.md for details):

- Batch sizes (actual vs configured)
- Processing duration per batch
- Failed message rates
- DLQ message rates
- Retry counts

Example telemetry handler:

```elixir
:telemetry.attach(
  "batch-metrics",
  [:kafee, :batch, :process_end],
  fn _event, measurements, metadata, _config ->
    Logger.info("Batch processed",
      duration_ms: measurements.duration / 1_000_000,
      message_count: measurements.message_count,
      failed_count: measurements.failed_count,
      topic: metadata.topic
    )
  end,
  nil
)
```

## Best Practices

1. **Start with conservative settings** - Small batch sizes and short timeouts
2. **Monitor and adjust** - Use telemetry to find optimal settings
3. **Handle partial failures** - Design for resilience
4. **Test timeout behavior** - Understand how your system behaves with partial batches
5. **Consider message ordering** - Batching can affect ordering guarantees
6. **Plan for back-pressure** - Set appropriate in-flight limits

## Common Issues

### Batches Not Processing (Timeout Limitation)

**Important:** Batch timeouts are only checked when new messages arrive from Kafka. This is a common pattern in Kafka consumers (including popular libraries like Elsa) because:

1. Kafka consumers are event-driven, not timer-driven
2. Adding internal timers would complicate the consumer implementation
3. Production systems typically have steady message flow making this a non-issue

**Workarounds for Low-Volume Topics:**

1. **Heartbeat Messages** - Send periodic messages to trigger batch processing:
   ```elixir
   # Simple heartbeat producer
   :timer.send_interval(1000, fn ->
     MyProducer.produce(%{type: "heartbeat"}, topic: "my-topic")
   end)
   
   # Filter them out in your consumer
   def handle_batch(messages) do
     real_messages = Enum.reject(messages, &(&1.value.type == "heartbeat"))
     # Process real messages...
   end
   ```

2. **Reduce Batch Size** - For low-volume topics, use smaller batches:
   ```elixir
   batch: [size: 5, timeout: 1000]  # Process after just 5 messages
   ```

3. **Use Single-Message Mode** - For very low volume, skip batching:
   ```elixir
   mode: :single_message  # Process each message immediately
   ```

4. **External Trigger** - Create a separate process that produces flush messages:
   ```elixir
   # See Kafee.Producer.AsyncWorker for a similar pattern
   Process.send_after(self(), :check_timeout, timeout_ms)
   ```

This design decision aligns with other production Kafka libraries and keeps the implementation simpler and more reliable.

### Memory Issues

If you see memory problems:
- Reduce batch_size
- Reduce max_in_flight_batches  
- Check message sizes with telemetry

### Partial Batch Processing

Due to how Kafka consumers work, the last partial batch only processes when:
- New messages arrive after the timeout
- The consumer shuts down gracefully

This is normal behavior and rarely an issue in production with steady message flow.

## Performance Benchmarks

Our realistic performance testing simulates real-world database operations and shows significant improvements with batch processing:

### Test Scenario
- 200 messages total
- Single message: 5ms database INSERT latency per message
- Batch: 10ms for entire batch INSERT (regardless of size)

### Results

| Batch Size | Throughput (msg/s) | Speedup vs Single | Use Case |
|------------|-------------------|-------------------|----------|
| 1 (single) | ~88               | 1.0x (baseline)   | Low latency, simple operations |
| 10         | ~837              | 9.5x              | Balanced latency/throughput |
| 50         | ~3,509            | 40x               | High throughput data pipelines |

### Why Batch Processing is Faster

1. **Database Transaction Overhead**: Single messages require individual transactions, while batches share one
2. **Network Round-trips**: Fewer acknowledgments to Kafka broker
3. **Connection Pooling**: Better utilization of database connections
4. **I/O Optimization**: Operating system and database can optimize bulk operations

### Real-World Example

**Single Message Processing:**
```
Message 1: Connect → BEGIN → INSERT → COMMIT → Ack (5ms)
Message 2: Connect → BEGIN → INSERT → COMMIT → Ack (5ms)
...
Total: 1000ms for 200 messages (minimum)
```

**Batch Processing (size 50):**
```
Batch 1: Connect → BEGIN → INSERT 50 rows → COMMIT → Ack (10ms)
Batch 2: Connect → BEGIN → INSERT 50 rows → COMMIT → Ack (10ms)
Batch 3: Connect → BEGIN → INSERT 50 rows → COMMIT → Ack (10ms)
Batch 4: Connect → BEGIN → INSERT 50 rows → COMMIT → Ack (10ms)
Total: 40ms for 200 messages (40x faster!)
```

Run the performance test at `test/kafee/consumer/batch_performance_realistic_test.exs` to see batch processing performance improvements in your environment.