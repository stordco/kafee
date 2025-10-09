# Implementation Plan for Batch Processing in Kafee BrodAdapter

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
  - `async_batch` (default: false) - Whether to process messages within a batch asynchronously
- Change `message_type` from `:message` to `:message_set` when batching is enabled
- Maintain backward compatibility by defaulting to single message mode

### 2. Create New Batch Worker Module
- Create `Kafee.Consumer.BrodBatchWorker` to handle message sets
- Implement `handle_message/2` callback for `:brod_group_subscriber_v2` that:
  - Accumulates messages until batch_size or batch_timeout is reached
  - Transforms kafka messages to Kafee messages
  - Calls the consumer's batch handler
  - Handles acknowledgment strategies (commit after batch vs per message)

### 3. Update Consumer Behavior
- Add optional `handle_batch/1` callback to `Kafee.Consumer` behavior:
  ```elixir
  @callback handle_batch([Kafee.Consumer.Message.t()]) :: :ok | {:ok, failed_messages :: [Kafee.Consumer.Message.t()]}
  ```
- Default implementation iterates through messages calling existing `handle_message/1`
- Consumers can override for optimized batch processing (e.g., bulk database inserts)

### 4. Modify Adapter Interface
- Add `push_batch/3` function to `Kafee.Consumer.Adapter` module
- Implement batch-aware telemetry and OpenTelemetry tracing
- Support DataDog data streams for batch operations
- Handle partial batch failures gracefully

### 5. Error Handling Strategy
- Track individual message failures within a batch
- Support different acknowledgment strategies:
  - All-or-nothing: Only ack if entire batch succeeds
  - Best-effort: Ack successful messages, retry failures
  - Last-offset: Ack up to last successful message
- Call `handle_failure/2` for each failed message in the batch

### 6. Configuration Examples
```elixir
# Enable batching with defaults
use Kafee.Consumer,
  adapter: {Kafee.Consumer.BrodAdapter, [batch_size: 100]}

# Full configuration
use Kafee.Consumer,
  adapter: {Kafee.Consumer.BrodAdapter, [
    batch_size: 500,
    batch_timeout: 2000,
    async_batch: true,
    ack_strategy: :best_effort
  ]}

# Backward compatible (no batching)
use Kafee.Consumer,
  adapter: Kafee.Consumer.BrodAdapter
```

### 7. Testing Strategy
- Unit tests for batch accumulation logic
- Integration tests with Docker Kafka comparing throughput
- Error injection tests for partial batch failures
- Performance benchmarks: single vs various batch sizes
- Test consumer group rebalancing during batch processing

## Benefits
1. **Improved Throughput**: Process 100-1000x more messages per second
2. **Backward Compatible**: Existing consumers continue working unchanged
3. **Flexible**: Consumers can optimize for their use case
4. **Consistent**: Follows patterns from BroadwayAdapter

## Risks and Mitigations
1. **Increased Latency**: Mitigated by configurable batch_timeout
2. **Memory Usage**: Batches consume more memory - add max_batch_memory option if needed
3. **Complex Error Handling**: Clear documentation and examples for different strategies
4. **Message Ordering**: Async batching may affect order - document this clearly

## Alternative Approaches Considered
1. **Modify existing BrodWorker**: Rejected as it would break backward compatibility
2. **Force all consumers to implement batch handling**: Rejected as too disruptive
3. **Create separate BrodBatchAdapter**: Rejected as it would duplicate too much code

## Questions for Review
1. Should we support dynamic batch sizing based on message size/complexity?
2. Is the proposed error handling strategy sufficient for production use cases?
3. Should batch configuration be adjustable at runtime?
4. What metrics/logs would be most helpful for monitoring batch performance?