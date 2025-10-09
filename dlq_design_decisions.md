# Dead Letter Queue (DLQ) Design Decisions for Kafee

## Overview

Kafee provides optional, configurable Dead Letter Queue (DLQ) support to make error handling as easy as possible while maintaining flexibility for users who need custom implementations.

## Design Philosophy

### Hybrid Approach: Optional DLQ Support

1. **Provide optional, configurable DLQ support** that users can enable if they want the convenience
2. **Keep it flexible** so users can still implement their own error handling if needed
3. **Make it non-intrusive** - the DLQ feature should not affect users who don't want it

## Why Include Optional DLQ in Kafee

### Pros of Including Optional DLQ:
- **Consistency**: Provides a standard way to handle errors across different Kafee users
- **Convenience**: Users get DLQ functionality out-of-the-box with simple configuration
- **Best practices**: We can implement proven patterns (retry counts, error metadata, etc.)
- **Reduces boilerplate**: Users don't need to write the same DLQ code repeatedly
- **Still flexible**: Users can ignore it and implement their own if needed

## Implementation Details

### Configuration

#### Recommended: Shared DLQ Producer

For efficiency, we recommend setting up a single DLQ producer that all consumers can share:

```elixir
# In your application supervisor
children = [
  # Single DLQ producer for all consumers
  {Kafee.DLQProducer, 
    name: :dlq_producer,
    topic: "my-app-dlq",
    host: "localhost",
    port: 9092
  },
  
  # Your consumers reference the shared producer
  {MyConsumer, []},
  {AnotherConsumer, []}
]

# Consumer configuration
defmodule MyConsumer do
  use Kafee.Consumer,
    adapter: {BrodAdapter, [
      mode: :batch,
      acknowledgment: [
        strategy: :best_effort,
        dead_letter_producer: :dlq_producer,  # Reference shared producer
        dead_letter_max_retries: 3
      ]
    ]}
end
```

#### Alternative: Per-Consumer DLQ Configuration

If you need different DLQ topics or settings per consumer:

```elixir
# Per-consumer DLQ configuration
adapter: {BrodAdapter, [
  mode: :batch,
  acknowledgment: [
    strategy: :best_effort,
    dead_letter_topic: "orders-dlq",  # Consumer-specific topic
    dead_letter_max_retries: 5
  ]
]}

# Or disable DLQ by omitting configuration
adapter: {BrodAdapter, [
  mode: :batch,
  acknowledgment: [strategy: :all_or_nothing]
  # No DLQ config = handle errors yourself
]}
```

### What the Library Provides:
1. **Automatic retry tracking** - Attempt count in message headers
2. **Error metadata preservation** - Exception details, timestamp, original topic/partition
3. **Configurable retry attempts** - Set max retries before sending to DLQ
4. **Clean producer interface** - Automatic publishing to DLQ topic
5. **Proper error logging and telemetry** - Structured logs and metrics

### What Users Still Control:
1. **Whether to use DLQ at all** - It's opt-in via configuration
2. **Custom error categorization** - Via handle_dead_letter/2 callback
3. **DLQ message processing strategy** - How to handle messages in DLQ
4. **Integration with monitoring/alerting** - Custom telemetry handlers
5. **Custom retry logic** - Can implement their own if needed

## Message Format

### DLQ Message Headers
When sending a message to DLQ, Kafee adds the following headers:
- `x-original-topic`: The topic the message originally came from
- `x-original-partition`: The partition the message originally came from
- `x-original-offset`: The original offset of the message
- `x-failure-timestamp`: When the failure occurred (ISO8601)
- `x-failure-reason`: The error message or exception
- `x-retry-count`: Number of processing attempts
- `x-consumer-group`: The consumer group that failed to process

### DLQ Message Body
The original message body is preserved as-is to allow for reprocessing.

## Error Categories

Kafee distinguishes between:
1. **Retriable errors** - Transient failures that may succeed on retry
2. **Non-retriable errors** - Permanent failures that should go straight to DLQ
3. **Poison pills** - Messages that consistently cause consumer crashes

## Best Practices Implemented

1. **Retry before DLQ** - Messages are retried up to max_retries before DLQ
2. **Preserve original format** - DLQ messages maintain original structure
3. **Rich error metadata** - Comprehensive error context in headers
4. **Monitoring friendly** - Telemetry events for DLQ operations
5. **Configurable behavior** - Tune retries and strategies per consumer

## Comparison with Other Libraries

| Library | Built-in DLQ | Implementation |
|---------|--------------|----------------|
| Core Kafka (Java) | ❌ | Manual |
| Kafka Connect | ✅ | Config-based |
| Spring Kafka | ✅ | Annotation-based |
| Broadway (Elixir) | ❌ | User callback |
| Elsa (Elixir) | ❌ | Manual |
| **Kafee** | ✅ | Optional config |

## Shared DLQ Producer Benefits

Using a shared DLQ producer provides several advantages:

1. **Resource Efficiency**
   - Single Kafka connection for all DLQ operations
   - Reduced memory footprint (one producer vs many)
   - Better connection pooling and batching

2. **Operational Simplicity**
   - Single point to monitor DLQ health
   - Centralized configuration for DLQ settings
   - Easier to implement circuit breakers or rate limiting

3. **Performance**
   - Batching across multiple consumers improves throughput
   - Reduced network overhead
   - More efficient use of Kafka producer buffers

4. **Flexibility**
   - Can still use per-consumer DLQ when needed
   - Easy to switch between shared and dedicated producers
   - Supports multiple DLQ topics with single producer

## Migration Path

Users can adopt DLQ support incrementally:
1. Start with no DLQ (current behavior)
2. Add shared DLQ producer to supervisor tree
3. Configure consumers to use the shared producer
4. Optionally implement handle_dead_letter/2 for custom logic
5. Monitor and tune based on metrics
6. Move to per-consumer DLQ if specific requirements emerge

This approach aligns with Kafee's goal of making things easy while maintaining the flexibility that Elixir developers expect.