# Adapter Configuration Location Analysis

## Current Pattern (from README)

```elixir
defmodule MyConsumer do
  use Kafee.Consumer,
    adapter: Application.compile_env(:my_app, :kafee_consumer_adapter, nil),
    consumer_group_id: "my-app",
    topic: "my-topic"

  def handle_message(message) do
    :ok
  end
end
```

## Option 1: Mode Configuration in `use` Macro

```elixir
defmodule MyConsumer do
  use Kafee.Consumer,
    adapter: {Kafee.Consumer.BrodAdapter, [
      mode: :batch,
      batch: [size: 100, timeout: 2000],
      processing: [async: true, max_concurrency: 20]
    ]},
    consumer_group_id: "my-app",
    topic: "my-topic"

  def handle_batch(messages) do
    # Batch processing
    :ok
  end
end
```

**Pros:**
- Consistent with current Kafee patterns
- All consumer config in one place
- Self-contained consumer modules
- Works well with compile-time configuration

**Cons:**
- Can make the `use` macro verbose for complex configs
- Harder to share configurations across consumers

## Option 2: Separate Adapter Config

```elixir
# In config/config.exs
config :my_app, MyConsumer,
  adapter: {Kafee.Consumer.BrodAdapter, [
    mode: :batch,
    batch: [size: 100, timeout: 2000],
    processing: [async: true, max_concurrency: 20]
  ]}

# In consumer module
defmodule MyConsumer do
  use Kafee.Consumer,
    consumer_group_id: "my-app",
    topic: "my-topic"

  def handle_batch(messages) do
    :ok
  end
end
```

**Pros:**
- Cleaner consumer modules
- Easier to change config per environment
- Can share configs

**Cons:**
- Configuration split across files
- Less explicit about adapter being used
- Breaks current Kafee patterns

## Option 3: Hybrid Approach (Recommended)

Support both patterns - inline for simple cases, external for complex:

```elixir
# Simple single-message consumer
defmodule PaymentConsumer do
  use Kafee.Consumer,
    adapter: {Kafee.Consumer.BrodAdapter, mode: :single_message},
    consumer_group_id: "payments",
    topic: "payment-events"

  def handle_message(message) do
    :ok
  end
end

# Complex batch consumer with external config
defmodule AnalyticsConsumer do
  use Kafee.Consumer,
    adapter: Application.compile_env(:my_app, :analytics_consumer_adapter),
    consumer_group_id: "analytics",
    topic: "user-events"

  def handle_batch(messages) do
    :ok
  end
end
```

Where the config would be:

```elixir
# config/prod.exs
config :my_app, :analytics_consumer_adapter,
  {Kafee.Consumer.BrodAdapter, [
    mode: :batch,
    batch: [size: 1000, timeout: 5000, max_bytes: 10_485_760],
    processing: [async: true, max_concurrency: 50, max_in_flight_batches: 5],
    acknowledgment: [
      strategy: :best_effort,
      dead_letter_topic: "analytics-dlq",
      dead_letter_max_retries: 3
    ]
  ]}
```

## Real-World Examples

### 1. Simple Consumer (Inline Config)

```elixir
defmodule UserRegistrationConsumer do
  use Kafee.Consumer,
    adapter: {Kafee.Consumer.BrodAdapter, mode: :single_message},
    consumer_group_id: "user-registration",
    topic: "user-signups"

  def handle_message(%{value: user_data}) do
    UserService.create_user(user_data)
  end
end
```

### 2. Batch Consumer (Inline Config)

```elixir
defmodule LogAggregatorConsumer do
  use Kafee.Consumer,
    adapter: {Kafee.Consumer.BrodAdapter, [
      mode: :batch,
      batch: [size: 500, timeout: 5000]
    ]},
    consumer_group_id: "log-aggregator",
    topic: "application-logs"

  def handle_batch(messages) do
    LogStorage.bulk_insert(messages)
  end
end
```

### 3. Complex Consumer (External Config)

```elixir
defmodule RealtimeAnalyticsConsumer do
  @adapter_config {Kafee.Consumer.BrodAdapter, [
    mode: :batch,
    batch: [size: 100, timeout: 1000, max_bytes: 5_242_880],
    processing: [
      async: true,
      max_concurrency: System.schedulers_online() * 2,
      max_in_flight_batches: 3
    ],
    acknowledgment: [
      strategy: :best_effort,
      dead_letter_topic: "analytics-dlq",
      dead_letter_max_retries: 5
    ]
  ]}

  use Kafee.Consumer,
    adapter: Application.compile_env(:my_app, :analytics_adapter, @adapter_config),
    consumer_group_id: "realtime-analytics",
    topic: "user-activity"

  def handle_batch(messages) do
    # Complex processing
    Analytics.process_batch(messages)
  end
end
```

## Recommendation

Keep the configuration in the `use` macro to maintain consistency with current Kafee patterns. This approach:

1. **Maintains backward compatibility**
2. **Keeps all consumer configuration co-located**
3. **Is explicit about what adapter and mode is being used**
4. **Allows using Application.compile_env for environment-specific configs**
5. **Follows the pattern established by other Elixir libraries like Ecto and Phoenix**

The key is to make the inline configuration as clean as possible:
- Simple configs can be inline
- Complex configs can use module attributes or Application.compile_env
- The structure should be clear and well-documented