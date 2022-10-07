defmodule Kafee.Producer.AsyncBackend do
  @moduledoc """
  This is an asynchronous backend for sending messages to Kafka. It utilizes a
  `Registry` and `DynamicSupervisor` to start a `Kafee.Producer.AsyncWorker`
  process for every topic * partition we send messages to.

  The supervisor tree will look something similar to this when in use:

  ```mermaid
  graph TD
    M[MyProducer]
    B[Kafee.Producer.AsyncBackend]
    K[Kafee.Application]

    K --> R[Kafee.Producer.AsyncRegistry]

    M --> B
    B --> U[:brod_client]
    B --> S[Kafee.Producer.AsyncSupervisor]

    S --> |"topic: 1, partition: 0"| W1[Kafee.Producer.AsyncWorker]
    S --> |"topic: 1, partition: 1"| W2[Kafee.Producer.AsyncWorker]
    S --> |"topic: 2, partition: 0"| W4[Kafee.Producer.AsyncWorker]
  ```

  For the process of queuing messages, it looks something like this:

  ```mermaid
  sequenceDiagram
    participant P as MyProducer
    participant B as Kafee.Producer.AsyncBackend
    participant S as Kafee.Producer.AsyncSupervisor
    participant W as Kafee.Producer.AsyncWorker

    P->>+B: get_partition/4
    B-->>-P: 2

    P->>+B: produce/4
    B->>+S: queue/4
    Note over S,W: Creates AsyncWorker if it doesn't exist
    S->>+W: queue/2
    W-->>-P: :ok

    loop Every 10 seconds by default
        W->>+Kafka: send/4
        Kafka-->>-W: :ack
    end
  ```

  ## Error Handling

  Because this module sends messages async, we have to handle errors
  non blocking. In most cases this is a benefit because we can transparently
  handle common error cases. For instance, if your Kafka connection goes
  down, you don't lose your messages. They send right after reconnect.

  When the `Kafka.Producer.AsyncWorker` process exits, it attempts to
  synchronously send all remaining messages to Kafka. In the unlikely
  event that it fails, we dump all unsent messages to the logs.

  > #### Possible Data Loss {: .error}
  >
  > If you have messages waiting to be sent because you are unable to connect
  > to Kafka, and you close the application, all remaining messages will be
  > sent to the logs. Please ensure you have a proper log situation set up or
  > you may lose data.
  """

  use Supervisor

  alias Kafee.Producer.{AsyncSupervisor, Config}

  @doc false
  @impl true
  def init(%Config{} = config) do
    brod_endpoints = Config.brod_endpoints(config)
    brod_client_opts = Config.brod_client_config(config)

    children = [
      {:brod_client, [brod_endpoints, config.producer, brod_client_opts]},
      {Kafee.Producer.AsyncSupervisor, config}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def init(opts) do
    raise ArgumentError,
      message: """
      The `Kafee.Producer.AsyncBackend` module expects to be given
      a `Kafee.Producer.Config` struct on startup.

      Received:
      #{inspect(opts)}
      """
  end

  @doc """
  Starts a new `Kafee.Producer.AsyncBackend` process and associated children.
  """
  @spec start_link(Config.t()) :: Supervisor.on_start()
  def start_link(%Config{} = config) do
    Supervisor.start_link(__MODULE__, config)
  end

  @doc """
  Returns a partition number for the given message under a topic. This uses
  the underlying `:brod` library partitioning logic. The given partition
  function can either be `:random`, `:hash`, or a function. See
  `:brod.partition_fun()` for more details.

  ## Examples

      iex> partition(%Config{}, message)
      {:ok, 1}

  """
  @spec partition(Config.t(), map()) :: {:ok, :brod.partition()} | {:error, term()}
  def partition(%Config{producer: producer}, message) do
    with {:ok, partition_count} <- :brod.get_partitions_count(producer, message.topic) do
      partition_fun = :brod_utils.make_part_fun(message.partition_fun)
      partition_fun.(message.topic, partition_count, message.key, message.value)
    end
  end

  @doc """
  Sends all of the given messages to an `Kafee.Producer.AsyncWorker` queue
  to be sent to Kafka in the future.
  """
  def produce(%Config{} = config, messages) do
    # Here we partition the message, but we also strip the message down to just
    # a key value map, which is what's required by `:brod`. This saves us a
    # a little bit of queue space at the expense of time initially blocking
    # on produce request.
    message_partitions = Enum.group_by(messages, &message_partition_key/1, &strip_message/1)

    for {{topic, partition}, messages} <- message_partitions do
      :ok = AsyncSupervisor.queue(config, topic, partition, messages)
    end
  end

  defp message_partition_key(%{topic: topic, partition: partition}),
    do: {topic, partition}

  defp strip_message(%{key: key, value: value}), do: %{key: key, value: value}
end
