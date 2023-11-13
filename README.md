# Kafee

Let's get energized with Kafka!

Kafee is an abstraction layer above multiple different lower level Kafka libraries, while also adding features relevant to Stord. This allows switching between `:brod` or `Broadway` for message consuming with a quick configuration change and no code changes. Features include:

- Behaviour based adapters allowing quick low level changes.
- Built in support for testing without mocking.
- Automatic encoding and decoding of message values with `Jason` or `Protobuf`.
- `:telemetry` metrics for producing and consuming messages.
- Open Telemetry traces with correct attributes.
- DataDog data streams support via `data-streams-ex`.

## Installation

Just add [`kafee`](https://hex.pm/packages/stord/kafee) to your `mix.exs` file like so:

<!-- {x-release-please-start-version} -->
```elixir
def deps do
  [
    {:kafee, "~> 3.0.0", organization: "stord"}
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
