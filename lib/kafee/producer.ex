defmodule Kafee.Producer do
  @moduledoc """
  A module based Kafka producer with pluggable backends allowing for
  asynchronous, synchronous, and no-op sending of messages to Kafka.

  ## Configuration Loading

  Every `Kafee.Producer` can load configuration from three different places
  (in order):

  - The application configuration with `config :kafee, producer: []`
  - The module options with `use Kafee.Producer`
  - The init options with `{MyProducer, []}`

  ## Configuration Options

  All configurations specified will be put into the `Kafee.Producer.Config`
  struct. You can view that module for more specific information.

  - `producer_backend` The type backend module responsible for sending
    messages to Kafka. See `Kafee.Producer.Backend` for more details.

  - `hostname` (default: `localhost`)
  - `port` (default: `9092`)
  - `endpoints` Override the single hostname and port with a list of
    endpoints. See `:brod` for more information.

  - `username`
  - `password`
  - `ssl` (default: `false`)

  - `topic` An optional topic to automatically add to all messages sent
    via this module. Note, any topic set on the message itself will take
    priority.
  - `partition_fun` (default: `:hash`) The default partition function for
    all messages sent via this module. See `:brod` for more details on
    partitioning and the partition function.

  - `brod_client_opts` Any extra client options to be used when creating a
    `:brod_client`.
  - `brod_producer_opts` Any extra options to be used when creating a
    `:brod_producer`.

  - `kafee_async_worker_opts` Extra options to send to the
    `Kafee.Producer.AsyncWorker` module. This only has effect if you are
    using the `Kafee.Producer.AsyncBackend`.

  ## Using

  To get started simply make a module like so:

      defmodule MyProducer do
        use Kafee.Producer
      end

  At which point you will be able to do this:

      iex> :ok = MyProducer.produce([%Kafee.Producer.Message{
        key: "key",
        value: "value",
        topic: "my-topic"
      }])

  Though we don't recommend calling `produce/1` directly in your code.
  Instead, you should add some function heads to your module to handle
  transformation and partitioning.

      defmodule MyProducer do
        use Kafee.Producer

        def publish(:order_created, %Order{} = order)
          produce([%Kafee.Producer.Message{
            key: order.tenant_id,
            value: Jason.encode!(order),
            topic: "order-created"
          }])
        end
      end

  Then just safely call the `publish/2` function in your application.

      iex> :ok = MyProducer.publish(:order_created, order)

  ## Testing

  Kafee includes a `Kafee.Producer.TestBackend` to help test if messages
  were sent in your code. See `Kafee.Producer.TestBackend` and
  `Kafee.Testing` for more information.
  """

  alias Kafee.Producer.{Config, Message}

  @doc false
  defmacro __using__(module_opts \\ []) do
    quote do
      use Supervisor

      @doc false
      @impl true
      # credo:disable-for-lines:15 Credo.Check.Design.AliasUsage
      def init(init_opts \\ []) do
        # credo:disable-for-lines:2 Credo.Check.Warning.UnsafeToAtom
        config =
          [brod_client_id: Module.concat(__MODULE__, BrodClient), producer: __MODULE__]
          |> Kafee.Producer.Config.new()
          |> Kafee.Producer.Config.merge(Application.get_env(:kafee, :producer, []))
          |> Kafee.Producer.Config.merge(unquote(module_opts))
          |> Kafee.Producer.Config.merge(init_opts)
          |> Kafee.Producer.Config.validate!()

        children = [
          {Kafee.Producer.Config, config},
          {config.producer_backend, config}
        ]

        Supervisor.init(children, strategy: :one_for_one)
      end

      @doc """
      Starts a new `Kafee.Producer` process and associated children.
      """
      @spec start_link(Keyword.t()) :: Supervisor.on_start()
      def start_link(opts) do
        Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @doc """
      Sends a single message to the configured backend to be
      sent to Kafka. See `Kafee.Produce.normalize/1` and
      `Kafee.Producer.produce/2` functions for more information.
      """
      @spec produce(Kafee.Producer.Message.partial()) :: :ok | {:error, term()}
      def produce(%Kafee.Producer.Message{} = message) do
        produce([message])
      end

      @doc """
      Sends a list of messages to the configured backend to be
      sent to Kafka. See `Kafee.Producer.normalize/2` and
      `Kafee.Producer.produce/2` functions for more information.
      """
      @spec produce([Kafee.Producer.Message.partial()]) :: :ok | {:error, term()}
      def produce(messages) do
        messages
        |> Kafee.Producer.normalize(__MODULE__)
        |> Kafee.Producer.validate_batch!()
        |> Kafee.Producer.produce(__MODULE__)
      end
    end
  end

  @doc """
  Normalizes a list of messages by partitioning them and setting
  producer default values. This is the last step before sending them
  the backend and eventually Kafka.

  ## Examples

      iex> normalize([%Message{}], MyProducer)
      [%Message{}]

  """
  @spec normalize([Message.partial()], atom()) :: [Message.t()]
  def normalize(messages, producer) do
    config = Config.get(producer)

    Enum.map(messages, fn message ->
      message =
        message
        |> maybe_put_topic(config)
        |> maybe_put_partition_fun(config)

      case Map.get(message, :partition, nil) do
        int when is_integer(int) ->
          message

        nil ->
          {:ok, partition} = config.producer_backend.partition(config, message)
          Map.put(message, :partition, partition)
      end
    end)
  end

  defp maybe_put_partition_fun(%{partition_fun: nil} = message, %{partition_fun: partition_fun}),
    do: Map.put(message, :partition_fun, partition_fun)

  defp maybe_put_partition_fun(message, _config), do: message

  defp maybe_put_topic(%{topic: nil} = message, %{topic: topic}),
    do: Map.put(message, :topic, topic)

  defp maybe_put_topic(message, _config), do: message

  @doc """
  Validates a list of messages. See `validate!/1` for more information.

  ## Examples

      iex> validate!([%Message{topic: "test", partition: 1}])
      [%Message{topic: "test", partition: 1}]

  """
  @spec validate_batch!(list(Message.partial())) :: list(Message.t())
  def validate_batch!(messages) do
    Enum.map(messages, fn message -> validate!(message) end)
  end

  @doc """
  Validates messages to ensure they have a topic and partition before
  sending them into a queue. This is designed to error early and
  in-line before it gets to a queue, where the problem would be much,
  _much_ bigger.

  """
  @spec validate!(Message.partial()) :: Message.t()
  def validate!(%Message{topic: nil} = message),
    do:
      raise(RuntimeError,
        message: """
        `Kafee.Producer.Message` is missing a topic to send to.

        Message:
        #{inspect(message)}
        """
      )

  def validate!(%Message{partition: nil} = message),
    do:
      raise(RuntimeError,
        message: """
        `Kafee.Producer.Message` is missing a partition to send to.

        Message:
        #{inspect(message)}
        """
      )

  def validate!(%Message{} = message), do: message

  @doc """
  Produces a list of messages depending on the configuration set
  in the producer.

  ## Examples

      iex> produce([message], MyProducer)
      :ok

  """
  @spec produce([Message.t()], atom) :: :ok | {:error, term()}
  def produce(messages, producer) do
    config = Config.get(producer)
    config.producer_backend.produce(config, messages)
  end
end
