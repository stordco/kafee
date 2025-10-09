# Implementation Plan for Batch Processing in Kafee BrodAdapter (v2)

## Context
The Kafee library is an Elixir abstraction layer for Kafka operations. Currently, the BrodAdapter processes messages one at a time, which limits throughput. This plan outlines how to add batch processing support to improve performance.

## Current State Analysis

1. **Single Message Processing**: The BrodAdapter uses `message_type: :message`, processing one message at a time synchronously
2. **Comparison**: The BroadwayAdapter already supports batching with configurable batch sizes, timeouts, and async processing
3. **Brod Capability**: The underlying brod_group_subscriber_v2 supports `message_type: :message_set` for batch delivery

## Implementation Plan

### 1. Update BrodAdapter Configuration
- Add new options to the adapter schema:
  - `batch_size` (default: 100) - Maximum messages per batch
  - `batch_timeout` (default: 1000ms) - Maximum wait time before processing partial batch
  - `max_batch_bytes` (default: 1MB) - Maximum batch size in bytes
  - `async_batch` (default: false) - Whether to process messages within a batch asynchronously
  - `max_concurrency` (default: 10) - When async_batch is true, limit concurrent tasks
  - `max_in_flight_batches` (default: 3) - Back-pressure mechanism
  - `ack_strategy` (default: :all_or_nothing) - How to handle partial failures
  - `dead_letter_config` (optional) - DLQ configuration
- Change `message_type` from `:message` to `:message_set` when batching is enabled
- Maintain backward compatibility by defaulting to single message mode

### 2. Create New Batch Worker Module
- Create `Kafee.Consumer.BrodBatchWorker` to handle message sets
- Implement back-pressure mechanism:
  - Track number of in-flight batches
  - Pause fetching when limit reached
  - Resume when batches complete
- Implement `handle_message/2` callback that:
  - Accumulates messages until batch_size, batch_timeout, or max_batch_bytes is reached
  - Transforms kafka messages to Kafee messages
  - Calls the consumer's batch handler
  - Handles acknowledgment based on strategy

### 3. Update Consumer Behavior
- Add optional callbacks to `Kafee.Consumer` behavior:
  ```elixir
  @callback handle_batch([Kafee.Consumer.Message.t()]) :: 
    :ok | 
    {:ok, failed_messages :: [Kafee.Consumer.Message.t()]} |
    {:error, reason :: term()}
    
  @callback handle_dead_letter(Kafee.Consumer.Message.t(), reason :: term()) :: :ok
  ```
- Default `handle_batch/1` implementation iterates through messages calling existing `handle_message/1`
- Default `handle_dead_letter/2` logs the failure

### 4. Implement Robust Error Handling
- Acknowledgment strategies:
  - `:all_or_nothing` - Only ack if entire batch succeeds (safest, default)
  - `:best_effort` - Ack successful messages, retry failures
  - `:last_successful` - Ack up to last successful message
- Dead Letter Queue support:
  - Track retry count per message
  - Route to DLQ after configurable max retries
  - Support custom DLQ topic naming
- Handle "poison pill" messages gracefully

### 5. Modify Adapter Interface
- Add `push_batch/3` function to `Kafee.Consumer.Adapter` module
- Implement comprehensive telemetry:
  ```elixir
  # Batch-level events
  :telemetry.execute([:kafee, :consumer, :batch, :start], %{count: batch_size}, metadata)
  :telemetry.execute([:kafee, :consumer, :batch, :stop], %{duration: duration, failed_count: failed}, metadata)
  
  # Message-level events (aggregated)
  :telemetry.execute([:kafee, :consumer, :messages, :processed], %{count: processed_count}, metadata)
  ```
- Enhanced OpenTelemetry tracing for batch operations
- DataDog data streams support for batch metrics

### 6. Async Processing Implementation
- Use `Task.async_stream/3` with `:max_concurrency` option
- Ordered vs unordered processing based on configuration
- Proper error aggregation from concurrent tasks
- Memory-aware task spawning

### 7. Configuration Examples
```elixir
# Basic batching
use Kafee.Consumer,
  adapter: {Kafee.Consumer.BrodAdapter, [batch_size: 100]}

# Advanced configuration
use Kafee.Consumer,
  adapter: {Kafee.Consumer.BrodAdapter, [
    batch_size: 500,
    batch_timeout: 2000,
    max_batch_bytes: 5_000_000,  # 5MB
    async_batch: true,
    max_concurrency: 20,
    max_in_flight_batches: 5,
    ack_strategy: :best_effort,
    dead_letter_config: [
      topic: "dead-letter-queue",
      max_retries: 3
    ]
  ]}

# Runtime configuration updates
GenServer.cast(consumer_pid, {:update_batch_config, [batch_size: 1000]})
```

### 8. Monitoring & Observability
Key metrics to implement:
- `kafee.consumer.batch.processed.count` - Total batches (tags: status)
- `kafee.consumer.messages.processed.count` - Total messages (tags: status)
- `kafee.consumer.batch.processing.duration` - Processing time distribution
- `kafee.consumer.batch.size` - Actual batch sizes distribution
- `kafee.consumer.batch.queue.depth` - In-flight batches gauge
- `kafee.consumer.dead_letter.sent.count` - DLQ messages counter

Structured logging:
- INFO: Batch completion summaries
- WARN: Partial failures with details
- ERROR: Complete batch failures
- DEBUG: Individual message failures (opt-in)

### 9. Testing Strategy
- Unit tests:
  - Batch accumulation logic with size/time/bytes limits
  - Back-pressure mechanism
  - Each acknowledgment strategy
  - DLQ routing logic
- Integration tests:
  - Docker Kafka throughput benchmarks
  - Consumer group rebalancing during batch processing
  - Poison pill message handling
  - Memory usage under load
- Performance tests:
  - Single vs batch throughput comparison
  - Async vs sync batch processing
  - Various batch sizes and concurrency levels

### 10. Future Enhancements (Post-MVP)
- Dynamic batch sizing based on processing time
- Batch compression before processing
- Metrics-based auto-tuning
- Circuit breaker for failing partitions

## Benefits
1. **10-100x Throughput Improvement**: Based on batch size and processing efficiency
2. **Production-Ready**: Back-pressure, DLQ, and monitoring built-in
3. **Backward Compatible**: Zero changes for existing consumers
4. **Flexible**: Multiple strategies for different use cases
5. **Observable**: Rich metrics and logging for operations

## Risks and Mitigations
1. **Memory Pressure**: Mitigated by max_batch_bytes and back-pressure
2. **Increased Latency**: Configurable batch_timeout for latency-sensitive apps
3. **Complexity**: Comprehensive documentation and examples
4. **Async Ordering**: Clear documentation, ordered option available
5. **Poison Pills**: DLQ prevents partition blocking

## Migration Path
1. Phase 1: Deploy with batching disabled (default)
2. Phase 2: Enable batching with small sizes (10-50)
3. Phase 3: Gradually increase based on metrics
4. Phase 4: Enable async processing if beneficial