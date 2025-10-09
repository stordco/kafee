# Kafee Telemetry Events

This document describes all telemetry events emitted by Kafee, including those for the new batch processing functionality.

## Consumer Telemetry Events

### Single Message Processing

#### `[:kafee, :consume]`

Emitted when a single message is processed by a consumer.

**Measurements:**
- `duration` - Time taken to process the message (emitted by `:telemetry.span`)

**Metadata:**
- `module` - The consumer module processing the message

### Batch Processing

#### `[:kafee, :consume_batch]`

Emitted when a batch of messages is processed by a consumer.

**Measurements:**
- `duration` - Time taken to process the entire batch (emitted by `:telemetry.span`)
- `batch_size` - Number of messages in the batch (in metadata for span)
- `failed_count` - Number of messages that failed processing (in span result metadata)
- `success_count` - Number of messages successfully processed (in span result metadata)

**Metadata:**
- `module` - The consumer module processing the batch
- `batch_size` - Number of messages in the batch
- `topic` - Kafka topic
- `partition` - Kafka partition

#### `[:kafee, :batch, :started]`

Emitted when a new batch accumulation starts (first message in a batch).

**Measurements:**
- `message_count` - Number of messages that started the batch
- `batch_bytes` - Total size of messages in bytes

**Metadata:**
- `topic` - Kafka topic
- `partition` - Kafka partition
- `consumer_group` - Kafka consumer group
- `consumer` - Consumer module

#### `[:kafee, :batch, :accumulated]`

Emitted when messages are added to an existing batch.

**Measurements:**
- `message_count` - Number of messages being added
- `total_messages` - Total messages in batch after addition
- `total_bytes` - Total size of batch in bytes

**Metadata:**
- `topic` - Kafka topic
- `partition` - Kafka partition
- `consumer_group` - Kafka consumer group
- `consumer` - Consumer module

#### `[:kafee, :batch, :process_start]`

Emitted when batch processing begins.

**Measurements:**
- `message_count` - Number of messages being processed
- `batch_bytes` - Total size of batch in bytes
- `async` - Boolean indicating if async processing is used
- `ack_strategy` - The acknowledgment strategy (`:all_or_nothing`, `:best_effort`, `:last_successful`)

**Metadata:**
- `topic` - Kafka topic
- `partition` - Kafka partition
- `consumer_group` - Kafka consumer group
- `consumer` - Consumer module

#### `[:kafee, :batch, :process_end]`

Emitted when batch processing completes successfully.

**Measurements:**
- `duration` - Time taken to process the batch (in native time units)
- `message_count` - Total number of messages processed
- `failed_count` - Number of messages that failed
- `success_count` - Number of messages successfully processed

**Metadata:**
- `topic` - Kafka topic
- `partition` - Kafka partition
- `consumer_group` - Kafka consumer group
- `consumer` - Consumer module
- `ack_strategy` - The acknowledgment strategy used

#### `[:kafee, :batch, :process_error]`

Emitted when batch processing fails with an error.

**Measurements:**
- `duration` - Time taken before the error occurred (in native time units)
- `message_count` - Number of messages that were being processed

**Metadata:**
- `topic` - Kafka topic
- `partition` - Kafka partition
- `consumer_group` - Kafka consumer group
- `consumer` - Consumer module
- `error` - The error that occurred

#### `[:kafee, :batch, :message_retry]`

Emitted when a message failure triggers a retry.

**Measurements:**
- `retry_count` - Current retry attempt number
- `max_retries` - Maximum retries allowed before DLQ

**Metadata:**
- `topic` - Kafka topic
- `partition` - Kafka partition
- `offset` - Message offset
- `consumer_group` - Kafka consumer group
- `consumer` - Consumer module

#### `[:kafee, :batch, :dlq_sent]`

Emitted when a message is successfully sent to the Dead Letter Queue.

**Measurements:**
- `duration` - Time taken to send to DLQ (in native time units)
- `retry_count` - Number of retries before sending to DLQ

**Metadata:**
- `topic` - Original Kafka topic
- `partition` - Original Kafka partition
- `offset` - Original message offset
- `dlq_topic` - Dead Letter Queue topic
- `consumer_group` - Kafka consumer group
- `consumer` - Consumer module

#### `[:kafee, :batch, :dlq_error]`

Emitted when sending a message to the Dead Letter Queue fails.

**Measurements:**
- `duration` - Time taken before the error (in native time units)
- `retry_count` - Number of retries before DLQ attempt

**Metadata:**
- `topic` - Original Kafka topic
- `partition` - Original Kafka partition
- `offset` - Original message offset
- `dlq_topic` - Dead Letter Queue topic
- `consumer_group` - Kafka consumer group
- `consumer` - Consumer module
- `error` - The error that occurred

## Producer Telemetry Events

### `[:kafee, :queue]`

Emitted by async producer when messages are queued.

**Measurements:**
- `count` - Number of messages in the queue

**Metadata:**
- `topic` - Kafka topic
- `partition` - Kafka partition

## Example Usage

To handle these telemetry events, attach handlers in your application:

```elixir
# In your Application.start/2 or similar
:telemetry.attach_many(
  "kafee-batch-handler",
  [
    [:kafee, :batch, :started],
    [:kafee, :batch, :process_end],
    [:kafee, :batch, :process_error],
    [:kafee, :batch, :dlq_sent],
    [:kafee, :batch, :dlq_error]
  ],
  &handle_event/4,
  nil
)

defp handle_event([:kafee, :batch, :process_end], measurements, metadata, _config) do
  Logger.info(
    "Batch processed in #{measurements.duration / 1_000_000}ms",
    topic: metadata.topic,
    partition: metadata.partition,
    success_count: measurements.success_count,
    failed_count: measurements.failed_count
  )
end

defp handle_event([:kafee, :batch, :dlq_sent], measurements, metadata, _config) do
  Logger.warning(
    "Message sent to DLQ after #{measurements.retry_count} retries",
    original_topic: metadata.topic,
    dlq_topic: metadata.dlq_topic,
    offset: metadata.offset
  )
end

# ... handle other events
```

## Metrics Recommendations

Based on these telemetry events, you might want to track:

1. **Batch Processing Performance**
   - Average batch processing time
   - Batch size distribution
   - Success/failure rates per consumer

2. **Message Reliability**
   - Retry rates per topic/consumer
   - DLQ message rates
   - Time between retries

3. **System Health**
   - Queue depths (for async producers)
   - In-flight batch counts
   - Back-pressure occurrences

4. **Consumer Performance**
   - Messages processed per second
   - Batch accumulation patterns
   - Processing strategy effectiveness