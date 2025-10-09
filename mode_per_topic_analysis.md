# Different Modes Per Topic/Consumer Analysis

## Realistic Use Cases

### 1. Mixed Event Types in One System

```elixir
# High-volume analytics events - batch for throughput
defmodule Analytics.PageViewConsumer do
  use Kafee.Consumer,
    adapter: {BrodAdapter, [
      mode: :batch,
      batch: [size: 1000, timeout: 5000],
      processing: [async: true, max_concurrency: 50]
    ]},
    topic: "page-views"
    
  def handle_batch(messages) do
    # Bulk insert into ClickHouse/BigQuery
    Analytics.bulk_insert(messages)
  end
end

# Critical payment events - single message for reliability
defmodule Payments.TransactionConsumer do
  use Kafee.Consumer,
    adapter: {BrodAdapter, mode: :single_message},
    topic: "payment-transactions"
    
  def handle_message(message) do
    # Process each payment individually with full error handling
    Payments.process_transaction(message)
  end
end

# Order updates - small batches for balance
defmodule Orders.UpdateConsumer do
  use Kafee.Consumer,
    adapter: {BrodAdapter, [
      mode: :batch,
      batch: [size: 10, timeout: 1000],
      acknowledgment: [strategy: :all_or_nothing]
    ]},
    topic: "order-updates"
    
  def handle_batch(messages) do
    # Process related orders together for efficiency
    Orders.bulk_update(messages)
  end
end
```

### 2. Same Topic, Different Processing Requirements

Sometimes you need different processing strategies for the same topic:

```elixir
# Real-time alerting - process immediately
defmodule Monitoring.RealTimeAlertConsumer do
  use Kafee.Consumer,
    adapter: {BrodAdapter, mode: :single_message},
    topic: "system-metrics",
    consumer_group_id: "realtime-alerts"
    
  def handle_message(%{value: %{"severity" => "critical"} = metric}) do
    Alerting.send_immediate_alert(metric)
  end
  
  def handle_message(_), do: :ok  # Skip non-critical
end

# Historical analysis - batch for efficiency
defmodule Monitoring.MetricsAggregatorConsumer do
  use Kafee.Consumer,
    adapter: {BrodAdapter, [
      mode: :batch,
      batch: [size: 5000, timeout: 30_000],  # 30 second windows
      processing: [async: true]
    ]},
    topic: "system-metrics",
    consumer_group_id: "metrics-aggregator"
    
  def handle_batch(messages) do
    # Aggregate and store in time-series DB
    TimeSeries.store_aggregated(messages)
  end
end
```

### 3. Migration Scenarios

During system migrations, you might run both modes:

```elixir
# Legacy processor - one at a time
defmodule Legacy.OrderProcessor do
  use Kafee.Consumer,
    adapter: {BrodAdapter, mode: :single_message},
    topic: "orders-v1"
    
  def handle_message(message) do
    # Old processing logic
    LegacySystem.process_order(message)
  end
end

# New processor - batch optimized
defmodule Modern.OrderProcessor do
  use Kafee.Consumer,
    adapter: {BrodAdapter, [
      mode: :batch,
      batch: [size: 100, timeout: 2000],
      processing: [async: true, max_concurrency: 20],
      acknowledgment: [
        strategy: :best_effort,
        dead_letter_topic: "orders-dlq"
      ]
    ]},
    topic: "orders-v2"
    
  def handle_batch(messages) do
    # New batch-optimized processing
    ModernSystem.bulk_process_orders(messages)
  end
end
```

## Configuration Patterns

### 1. Application Config with Overrides

```elixir
# config/config.exs
config :my_app, :kafee_defaults,
  adapter: {BrodAdapter, mode: :single_message},
  host: "localhost",
  port: 9092

# config/prod.exs
config :my_app, :kafee_batch_defaults,
  adapter: {BrodAdapter, [
    mode: :batch,
    batch: [size: 100, timeout: 1000],
    processing: [async: true]
  ]},
  host: "kafka.prod.example.com",
  port: 9092

# In consumers
defmodule HighVolumeConsumer do
  use Kafee.Consumer,
    Application.get_env(:my_app, :kafee_batch_defaults)
    |> Keyword.put(:topic, "high-volume-events")
end

defmodule CriticalConsumer do
  use Kafee.Consumer,
    Application.get_env(:my_app, :kafee_defaults)
    |> Keyword.put(:topic, "critical-events")
end
```

### 2. Module Attributes for Reuse

```elixir
defmodule MyApp.Consumers do
  @batch_config [
    mode: :batch,
    batch: [size: 500, timeout: 5000],
    processing: [async: true, max_concurrency: 30]
  ]
  
  @single_config [mode: :single_message]
  
  defmodule UserEvents do
    use Kafee.Consumer,
      adapter: {BrodAdapter, @batch_config},
      topic: "user-events"
      
    def handle_batch(messages) do
      # Batch process user events
    end
  end
  
  defmodule PaymentEvents do
    use Kafee.Consumer,
      adapter: {BrodAdapter, @single_config},
      topic: "payment-events"
      
    def handle_message(message) do
      # Process payments one by one
    end
  end
end
```

### 3. Dynamic Configuration Based on Environment

```elixir
defmodule DynamicConsumer do
  def child_spec(opts) do
    env = System.get_env("ENVIRONMENT", "development")
    
    adapter_config = case env do
      "production" -> 
        {BrodAdapter, [
          mode: :batch,
          batch: [size: 1000, timeout: 5000],
          processing: [async: true, max_concurrency: 50]
        ]}
      
      "staging" ->
        {BrodAdapter, [
          mode: :batch,
          batch: [size: 100, timeout: 2000]
        ]}
      
      _ ->
        {BrodAdapter, mode: :single_message}
    end
    
    %{
      id: __MODULE__,
      start: {Kafee.Consumer, :start_link, [
        __MODULE__,
        [adapter: adapter_config, topic: opts[:topic]]
      ]}
    }
  end
  
  use Kafee.Consumer
  
  def handle_message(message), do: process(message)
  def handle_batch(messages), do: bulk_process(messages)
end
```

## Considerations

1. **Resource Allocation**: Different modes require different resources
   - Batch mode needs more memory
   - Single message mode might need more processes

2. **Error Handling**: Different strategies for different data
   - Financial data: all_or_nothing
   - Analytics: best_effort
   - Logs: last_successful

3. **Monitoring**: Different metrics matter
   - Batch: throughput, batch sizes, processing time
   - Single: latency, individual message processing time

4. **Testing**: Need different test strategies
   - Batch: test with various batch sizes
   - Single: test individual message scenarios

## Recommendation

The ability to configure different modes per consumer is essential for real-world applications. The proposed API design supports this well:

1. Each consumer module can specify its own adapter configuration
2. The mode is explicit and clear
3. Teams can optimize each data flow independently
4. Migration from single to batch (or vice versa) is straightforward