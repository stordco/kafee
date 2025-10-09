# Kafee

Let's get energized with Kafka!

Kafee is an abstraction layer above multiple different lower level Kafka libraries, while also adding features relevant to Stord. This allows switching between `:brod` or `Broadway` for message consuming with a quick configuration change and no code changes. Features include:

- Behaviour based adapters allowing quick low level changes.
- Built in support for testing without mocking.
- Automatic encoding and decoding of message values with `Jason` or `Protobuf`.
- `:telemetry` metrics for producing and consuming messages.
- Open Telemetry traces with correct attributes.
- DataDog data streams support via `data-streams-ex`.
- **High-performance batch processing** with **5-50x throughput improvement** for I/O operations.

## Installation

Just add [`kafee`](https://hex.pm/packages/stord/kafee) to your `mix.exs` file like so:

<!-- {x-release-please-start-version} -->

```elixir
def deps do
  [
    {:kafee, "~> 3.5.4", organization: "stord"}
  ]
end
```

<!-- {x-release-please-end} -->

## Published Documentation

Documentation is automatically generated and published to [HexDocs](https://stord.hexdocs.pm/kafee/readme.html) on new releases.

## Quick Start

Here are two very basic examples of using a consumer and producer module with Kafee. Not all available options are documented, so please look at the individual modules for more details.

### Consumers

You'll first setup a module for your consumer logic like so:

```elixir
defmodule MyConsumer do
  use Kafee.Consumer,
    adapter: Application.compile_env(:my_app, :kafee_consumer_adapter, nil),
    consumer_group_id: "my-app",
    topic: "my-topic"

  def handle_message(%Kafee.Consumer.Message{} = message) do
    # Do some message handling
    :ok
  end
end
```

Then just start the module in your application with the correct connection details:

```elixir
defmodule MyApplication do
  use Application

  def start(_type, _args) do
    children = [
      {MyConsumer, [
        host: "localhost",
        port: 9092,
        sasl: {:plain, "username", "password"},
        ssl: true
      ]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

And lastly, you'll want to set the consumer adapter in production. You can do this by adding this line to your `config/prod.exs` file:

```elixir
import Config

config :my_app, kafee_consumer_adapter: Kafee.Consumer.BroadwayAdapter
```

This will ensure that your consumer does not start in development or testing environments, but only runs in production.

For more details on the consumer module, view the [Kafee Consumer module documentation](https://stord.hexdocs.pm/kafee/Kafee.Consumer.html).

### Producers

So you want to send messages to Kafka eh? Well, first you will need to create a producer module like so:

```elixir
defmodule MyProducer do
  use Kafee.Producer,
    adapter: Application.compile_env(:my_app, :kafee_producer_adapter, nil),
    encoder: Kafee.JasonEncoderDecoder,
    topic: "my-topic",
    partition_fun: :hash

  # This is just a regular function that takes a struct from your
  # application and converts it to a `t:Kafee.Producer.Message/0`
  # struct and calls `produce/1`. Note that because we have the
  # `encoder` option set above, the `order` value will be JSON
  # encoded before sending to Kafka.
  def publish(:order_created, %Order{} = order) do
    produce(%Kafee.Producer.Message{
      key: order.tenant_id,
      value: order
    })
  end
end
```

Once your module is setup, you'll need to add it to the supervisor tree with connection details.

```elixir
defmodule MyApplication do
  use Application

  def start(_type, _args) do
    children = [
      {MyProducer, [
        host: "localhost",
        port: 9092,
        sasl: {:plain, "username", "password"},
        ssl: true
      ]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

And finally, you'll want to use another adapter in production. So set that up in your `config/prod.exs` file:

```elixir
import Config

config :my_app, kafee_producer_adapter: Kafee.Producer.AsyncAdapter
```

Once that is done, to publish a message simply run:

```elixir
MyProducer.publish(:order_created, %Order{})
```

All messages published _not_ in production will be a no-op. This means you do not need any Kafka instance setup to run in development. For testing, we recommend using the [`Kafee.Producer.TestAdapter`](https://stord.hexdocs.pm/kafee/Kafee.Producer.TestAdapter.html) adapter, allowing easier testing via the [`Kafee.Test`](https://stord.hexdocs.pm/kafee/Kafee.Test.html) module.

## Batch Processing

Kafee supports high-performance batch message processing through two different adapters, each with distinct characteristics:

### Adapter Comparison

| Feature | BroadwayAdapter | BrodAdapter (Batch Mode) |
|---------|-----------------|-------------------------|
| **Batching Type** | Automatic, Broadway-managed | Manual, time/size based |
| **Configuration** | `batch_size`, `batch_timeout` | `batch: [size, timeout, max_bytes]` |
| **Error Handling** | Per-message with Broadway pipeline | Per-batch with custom strategies |
| **Acknowledgment** | Automatic per-message | Configurable: all_or_nothing, best_effort, last_successful |
| **Use Case** | High concurrency, complex pipelines | Maximum throughput, bulk operations |
| **Concurrency** | Built-in via Broadway stages | Sequential batch processing |

### When to Use Each Adapter

**Use BroadwayAdapter when:**
- You need built-in concurrency and back-pressure
- You want automatic batching with minimal configuration
- Your processing pipeline has multiple stages
- You need per-message error handling and retries

**Use BrodAdapter Batch Mode when:**
- You need maximum control over batch formation
- You're doing bulk database operations or API calls
- You want to minimize Kafka broker interactions
- You need custom acknowledgment strategies

### Performance Results

Real-world performance improvements with batch processing (measured with database operations):

| Batch Size | Throughput (msg/s) | Speedup vs Single | 
|------------|-------------------|-------------------|
| 1 (single) | ~88               | 1.0x (baseline)   |
| 10         | ~837              | 9.5x              |
| 50         | ~3,509            | 40x               |

### Example: BroadwayAdapter with Batching

```elixir
defmodule MyBroadwayConsumer do
  use Kafee.Consumer

  @impl Kafee.Consumer
  def handle_message(message) do
    # Broadway automatically batches messages
    # but you process them individually
    process_message(message)
  end
end

{MyBroadwayConsumer, [
  adapter: {Kafee.Consumer.BroadwayAdapter, [
    batch_size: 50,
    batch_timeout: 1000
  ]},
  host: "localhost",
  port: 29092,
  topic: "high-volume-topic",
  consumer_group_id: "broadway-consumer"
]}
```

### Example: BrodAdapter Batch Mode

```elixir
defmodule MyBatchConsumer do
  use Kafee.Consumer

  @impl Kafee.Consumer
  def handle_batch(messages) do
    # You receive and process messages as a batch
    MyApp.bulk_insert_to_database(messages)
    :ok
  end
end

{MyBatchConsumer, [
  adapter: {Kafee.Consumer.BrodAdapter, [
    mode: :batch,
    batch: [
      size: 50,           # Max messages per batch
      timeout: 1000,      # Max wait time in ms
      max_bytes: 1048576  # Max batch size in bytes
    ],
    acknowledgment_strategy: :all_or_nothing
  ]},
  host: "localhost",
  port: 29092,
  topic: "high-volume-topic",
  consumer_group_id: "batch-processor"
]}
```

See the [Batch Processing Guide](BATCH_PROCESSING.md) for detailed configuration options and performance tuning.
