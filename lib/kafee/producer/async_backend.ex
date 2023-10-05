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

    P->>+B: get_partition/2
    B-->>-P: 2

    P->>+B: produce/2
    B->>+S: queue/4
    Note over S,W: Creates AsyncWorker if it doesn't exist
    S->>+W: queue/2
    W-->>-P: :ok

    loop
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

  @behaviour Kafee.Producer.Backend
  @behaviour Supervisor

  alias Kafee.Producer.{AsyncSupervisor, Config, Message}

  @doc """
  Child specification for the async worker backend. This starts
  a `Kafee.Producer.AsyncWorker` for every partition in the topic
  we send data to, as well as the lower level `:brod_client`.
  """
  @impl Kafee.Producer.Backend
  def child_spec([config]) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [config]},
      type: :supervisor
    }
  end

  @doc false
  def start_link(%Config{} = config) do
    Supervisor.start_link(__MODULE__, config, name: Kafee.Producer.Backend.process_name(config.producer))
  end

  @doc false
  @impl Supervisor
  def init(%Config{} = config) do
    brod_endpoints = Config.brod_endpoints(config)
    brod_client_opts = Config.brod_client_config(config)

    children = [
      %{
        id: config.brod_client_id,
        start: {:brod_client, :start_link, [brod_endpoints, config.brod_client_id, brod_client_opts]}
      },
      {Kafee.Producer.AsyncSupervisor, config}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def init(opts) do
    received = inspect(opts)

    raise ArgumentError,
      message: """
      The `Kafee.Producer.AsyncBackend` module expects to be given
      a `Kafee.Producer.Config` struct on startup.

      Received:
      #{received}
      """
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
  @impl Kafee.Producer.Backend
  def partition(%Config{brod_client_id: brod_client_id}, message) do
    with {:ok, partition_count} <- :brod.get_partitions_count(brod_client_id, message.topic) do
      partition_fun = :brod_utils.make_part_fun(message.partition_fun)
      partition_fun.(message.topic, partition_count, message.key, message.value)
    end
  end

  @doc """
  Sends all of the given messages to an `Kafee.Producer.AsyncWorker` queue
  to be sent to Kafka in the future.
  """
  @impl Kafee.Producer.Backend
  def produce(%Config{} = config, messages) do
    # Here we partition the message, but we also strip the message down to just
    # a key value map, which is what's required by `:brod`. This saves us a
    # a little bit of queue space at the expense of time initially blocking
    # on produce request.
    message_partitions = Enum.group_by(messages, &message_partition_key/1, &strip_message/1)

    for {{topic, partition}, messages} <- message_partitions do
      :ok = AsyncSupervisor.queue(config, topic, partition, messages)
    end

    :ok
  end

  defp message_partition_key(%Message{topic: topic, partition: partition}),
    do: {topic, partition}

  defp strip_message(%Message{} = message),
    do: Map.take(message, [:key, :value, :headers])
end
