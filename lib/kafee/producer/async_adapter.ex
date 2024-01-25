defmodule Kafee.Producer.AsyncAdapter do
  @options_schema NimbleOptions.new!(
                    connect_timeout: [
                      default: :timer.seconds(10),
                      doc: """
                      The timeout for `:brod` to connect to the Kafka cluster. This matches
                      how `Elsa` connects and is required to give enough time for Confluent
                      cloud connections.
                      """,
                      type: :non_neg_integer
                    ],
                    max_request_bytes: [
                      default: 1_040_384,
                      doc: """
                      The max amount of bytes Kafka can receive in a batch of messages.
                      By Kafka default, it's 1MB, but we shrink it a bit as an extra precaution.

                      If we receive a Kafka error about message size, we will attempt to shrink
                      the amount of messages we send in a batch to avoid blocking the whole
                      queue on a couple large messages.
                      """,
                      type: :non_neg_integer
                    ],
                    max_retries: [
                      default: -1,
                      doc: """
                      The maximum number of tries `:brod` will attempt to connect to the
                      Kafka cluster. We set this to `-1` by default to avoid outages and
                      node crashes.
                      """,
                      type: :integer
                    ],
                    retry_backoff_ms: [
                      default: 100,
                      doc: """
                      The retry backoff time in milliseconds.
                      """,
                      type: :integer
                    ],
                    send_timeout: [
                      default: :timer.seconds(10),
                      doc: """
                      The amount of time to wait for an acknowledgement from Kafka before
                      we consider it a failure and retry to send the message.
                      """,
                      type: :non_neg_integer
                    ],
                    throttle_ms: [
                      default: 100,
                      doc: """
                      The amount of time to wait before messages being queued will
                      send them to Kafka. Setting this to a larger number means larger
                      batches of messages being sent to once, but potentially more
                      memory in use for the queue.
                      """,
                      type: :non_neg_integer
                    ]
                  )

  # credo:disable-for-lines:8 /\.Readability\./
  @moduledoc """
  This is an asynchronous adapter for sending messages to Kafka. It utilizes a
  `Registry` and `DynamicSupervisor` to start a `Kafee.Producer.AsyncWorker`
  process for every topic * partition we send messages to.

  ## Options

  #{NimbleOptions.docs(@options_schema)}

  ## Supervisor Tree

  The supervisor tree will look something similar to this when in use:

  ```mermaid
  graph TD
    M[MyProducer as Kafee.Producer.AsyncAdapter]
    K[Kafee.Application]

    K --> R[Kafee.Registry]

    M --> U[MyProducer.BrodClient]

    M --> |"topic: 1, partition: 0"| W1[Kafee.Producer.AsyncWorker]
    M --> |"topic: 1, partition: 1"| W2[Kafee.Producer.AsyncWorker]
    M --> |"topic: 2, partition: 0"| W3[Kafee.Producer.AsyncWorker]
  ```

  For the process of queuing messages, it looks something like this:

  ```mermaid
  sequenceDiagram
    participant P as MyProducer
    participant A as Kafee.Producer.AsyncAdapter
    participant W as Kafee.Producer.AsyncWorker
    participant B as :brod

    P->>+A: produce/2

    A->>+B: get_partitions/2
    B->>-A: [1, 2, 3, 4]

    Note over A,W: Creates AsyncWorker if it doesn't exist
    A->>+W: queue/2
    W->>-A: :ok
    A->>-P: :ok

    loop
        W->>+B: send/4
        B-->>-W: :ack
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

  ## Telemetry Events

  - `kafee.queue.count` - The amount of messages in queue
    waiting to be sent to Kafka. This includes the number of messages currently
    in flight awaiting to be acknowledged from Kafka.

    We recommend capturing this with `last_value/2` like so:

      last_value(
        "kafee.queue.count",
        description: "The amount of messages in queue waiting to be sent to Kafka",
        tags: [:topic, :partition]
      )

  """

  @behaviour Kafee.Producer.Adapter
  @behaviour Supervisor

  alias Kafee.Producer.{AsyncWorker, Message}

  @doc false
  @impl Kafee.Producer.Adapter
  @spec start_link(module(), Kafee.Producer.options()) :: Supervisor.on_start()
  def start_link(producer, options) do
    Supervisor.start_link(__MODULE__, {producer, options}, name: producer)
  end

  @doc false
  @spec child_spec({module(), Kafee.Producer.options()}) :: :supervisor.child_spec()
  def child_spec({producer, options}) do
    default = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [{producer, options}]},
      type: :supervisor
    }

    Supervisor.child_spec(default, [])
  end

  @doc false
  @impl Supervisor
  def init({producer, options}) do
    adapter_options =
      case options[:adapter] do
        nil -> []
        adapter when is_atom(adapter) -> []
        {_adapter, adapter_options} -> adapter_options
      end

    with {:ok, adapter_options} <- NimbleOptions.validate(adapter_options, @options_schema) do
      children = [
        %{
          id: brod_client(producer),
          start:
            {:brod_client, :start_link,
             [
               [{options[:host], options[:port]}],
               brod_client(producer),
               client_config(options, adapter_options)
             ]},
          type: :worker,
          restart: :permanent,
          shutdown: 500
        }
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  defp client_config(options, adapter_options) do
    (options ++ adapter_options)
    |> Keyword.take([:connect_timeout, :max_retries, :retry_backoff_ms, :sasl, :ssl])
    |> Keyword.put(:allow_topic_auto_creation, true)
    |> Keyword.put(:auto_start_producers, true)
    |> Keyword.reject(fn {_k, v} -> is_nil(v) end)
  end

  @doc """
  Returns a list of valid partitions under a topic.

  ## Examples

      iex> partition(MyProducer, [])
      [1, 2, 3, 4]

  """
  @impl Kafee.Producer.Adapter
  @spec partitions(module(), Kafee.Producer.options()) :: [Kafee.partition()]
  def partitions(producer, options) do
    {:ok, partition_count} =
      producer
      |> brod_client()
      |> :brod.get_partitions_count(options[:topic])

    0
    |> Range.new(partition_count - 1)
    |> Enum.to_list()
  end

  @doc """
  Sends all of the given messages to an `Kafee.Producer.AsyncWorker` queue
  to be sent to Kafka in the future.
  """
  @impl Kafee.Producer.Adapter
  @spec produce([Message.input()], module(), Kafee.Producer.options()) :: :ok | {:error, term()}
  def produce(messages, producer, options) do
    message_groups =
      messages
      |> Enum.map(fn message ->
        message
        |> Message.set_module_values(producer, options)
        |> Message.encode(producer, options)
        |> Message.partition(producer, options)
        |> Message.set_request_id_from_logger()
        |> Message.validate!()
      end)
      |> Enum.group_by(fn %{topic: topic, partition: partition} -> {topic, partition} end)

    for {{topic, partition}, messages} <- message_groups do
      :ok = queue(producer, options, topic, partition, messages)
    end

    :ok
  end

  @spec queue(module(), Kafee.Producer.options(), Kafee.topic(), Kafee.partition(), [Message.t()]) ::
          :ok | {:error, term()}
  defp queue(producer, options, topic, partition, messages) do
    with {:ok, pid} <- get_or_create_worker(producer, options, topic, partition) do
      AsyncWorker.queue(pid, messages)
    end
  end

  @spec create_worker(module(), Kafee.Producer.options(), Kafee.topic(), Kafee.partition()) ::
          {:ok, pid()} | {:error, term()}
  defp create_worker(producer, options, topic, partition) do
    adapter_options =
      case options[:adapter] do
        nil -> []
        adapter when is_atom(adapter) -> []
        {_adapter, adapter_options} -> adapter_options
      end

    worker_options =
      adapter_options
      |> NimbleOptions.validate!(@options_schema)
      |> Keyword.take([:max_request_bytes, :send_timeout, :throttle_ms])
      |> Keyword.put(:brod_client_id, brod_client(producer))
      |> Keyword.put(:topic, topic)
      |> Keyword.put(:partition, partition)

    with {:error, {:already_started, pid}} <- Supervisor.start_child(producer, {AsyncWorker, worker_options}) do
      {:ok, pid}
    end
  end

  @spec get_worker(module(), Kafee.topic(), Kafee.partition()) :: {:ok, pid()} | {:error, :not_found}
  defp get_worker(producer, topic, partition) do
    {:via, Registry, {registry_name, registry_key}} =
      producer
      |> brod_client()
      |> AsyncWorker.process_name(topic, partition)

    case Registry.lookup(registry_name, registry_key) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @spec get_or_create_worker(module(), Kafee.Producer.options(), Kafee.topic(), Kafee.partition()) ::
          {:ok, pid()} | {:error, term()}
  defp get_or_create_worker(producer, options, topic, partition) do
    with {:error, :not_found} <- get_worker(producer, topic, partition) do
      create_worker(producer, options, topic, partition)
    end
  end

  @spec brod_client(module()) :: module()
  defp brod_client(producer) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(producer, "BrodClient")
  end
end
