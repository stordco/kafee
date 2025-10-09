# BrodAdapter API Design Options

## Current Approach (Implicit Mode via batch_size)

```elixir
# Single message mode (default)
adapter: {BrodAdapter, []}

# Batch mode
adapter: {BrodAdapter, [
  batch_size: 100,
  batch_timeout: 2000,
  max_batch_bytes: 5_000_000,
  async_batch: true,
  max_concurrency: 20,
  max_in_flight_batches: 5,
  ack_strategy: :best_effort,
  dead_letter_config: [topic: "dlq", max_retries: 3]
]}
```

**Pros:**
- Backward compatible by default
- Single configuration structure

**Cons:**
- Many options only make sense when batch_size > 1
- Not immediately clear which options apply when
- Implicit mode switching via batch_size value

## Option 1: Explicit Mode Configuration

```elixir
# Single message mode
adapter: {BrodAdapter, mode: :single_message}

# Batch mode with nested options
adapter: {BrodAdapter, [
  mode: :batch,
  batch_config: [
    size: 100,
    timeout: 2000,
    max_bytes: 5_000_000,
    async: true,
    max_concurrency: 20,
    max_in_flight: 5,
    ack_strategy: :best_effort
  ],
  dead_letter_config: [topic: "dlq", max_retries: 3]
]}
```

**Pros:**
- Explicit about processing mode
- Clear grouping of batch-specific options
- Easier to validate configurations

**Cons:**
- Breaking change for existing users
- More nested configuration

## Option 2: Separate Adapter Modules

```elixir
# Single message mode
adapter: Kafee.Consumer.BrodAdapter

# Batch mode
adapter: {Kafee.Consumer.BrodBatchAdapter, [
  batch_size: 100,
  batch_timeout: 2000,
  max_batch_bytes: 5_000_000,
  async: true,
  max_concurrency: 20,
  max_in_flight_batches: 5,
  ack_strategy: :best_effort,
  dead_letter_config: [topic: "dlq", max_retries: 3]
]}
```

**Pros:**
- Very clear which mode you're using
- Each adapter can have its own focused options
- No confusion about which options apply

**Cons:**
- More code duplication
- Users need to know about two adapters

## Option 3: Processing Strategy Pattern

```elixir
# Single message mode
adapter: {BrodAdapter, processing: :single}

# Batch mode
adapter: {BrodAdapter, [
  processing: {:batch, [
    size: 100,
    timeout: 2000,
    max_bytes: 5_000_000,
    async: true,
    max_concurrency: 20,
    max_in_flight: 5,
    ack_strategy: :best_effort
  ]},
  dead_letter_config: [topic: "dlq", max_retries: 3]
]}
```

**Pros:**
- Explicit strategy selection
- Options grouped with their strategy
- Extensible for future strategies

**Cons:**
- More complex configuration structure
- Still requires nested options

## Option 4: Flat Structure with Prefixes

```elixir
# Batch mode
adapter: {BrodAdapter, [
  processing_mode: :batch,  # or :single_message
  batch_size: 100,
  batch_timeout: 2000,
  batch_max_bytes: 5_000_000,
  batch_async: true,
  batch_max_concurrency: 20,
  batch_max_in_flight: 5,
  batch_ack_strategy: :best_effort,
  dead_letter_topic: "dlq",
  dead_letter_max_retries: 3
]}
```

**Pros:**
- Flat structure is simple
- Clear prefixing shows which options are batch-related
- Easy to add to existing schema

**Cons:**
- Lots of prefixed options
- Still have options that don't apply in single mode

## Questions for Review

1. Which approach provides the best developer experience?
2. Which is most idiomatic for Elixir libraries?
3. How important is backward compatibility vs clarity?
4. Should we consider deprecating the current approach and migrating to a clearer API?
5. Are there other patterns common in Elixir that would work better?

## Context

This is for Kafee, an Elixir Kafka abstraction library. The BrodAdapter currently uses `batch_size: 1` as an implicit switch between single-message and batch processing modes. We're trying to determine if this is the best approach or if we should be more explicit about the processing mode.