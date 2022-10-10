# Kafee

Let's get energized with Kafka!

## Goals

- [ ] Encapsulate message publishing
- [ ] Open telemetry support
- [ ] Retries
- [ ] Adaptable message encoding
  - [ ] JSON
  - [ ] Avro
  - [ ] Protobuf

## Installation

Just add [`kafee`](https://hex.pm/packages/stord/kafee) to your `mix.exs` file like so:

<!-- {x-release-please-start-version} -->
```elixir
def deps do
  [
    {:kafee, "~> 1.0.3", organization: "stord"}
  ]
end
```
<!-- {x-release-please-end} -->

## Published Documentation

Documentation is automatically generated and published to [HexDocs](https://stord.hexdocs.pm/kafee/readme.html) on new releases.

## Quick Start

### Producers

So you want to send messages to Kafka eh? Well, here is some code for you.

```elixir
defmodule MyProducer do
  use Kafee.Producer,
    producer_backend: Kafee.Producer.AsyncBackend,
    topic: "my-kafka-topic"

  def publish(:order_created, %Order{} = order) do
    produce([%Kafee.Producer.Message{
      key: order.tenant_id,
      value: Jason.encode!(order)
    }])
  end
end

defmodule MyApplication do
  use Application

  def start(_type, _args) do
    children = [
      {MyProducer, [
        host: "localhost",
        port: 9092,
        username: "username",
        password: "password",
        ssl: true,
        sasl: :plain
      ]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

Once that is done, to publish a message simply run:

```elixir
MyProducer.publish(:order_created, %Order{})
```

See the `Kafee.Producer` module for more options and information.
