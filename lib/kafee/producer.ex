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
    `Kafee.Producer.AsyncWorker` module. This only has an effect if you are
    using the `Kafee.Producer.AsyncBackend`.

  ## Using

  To get started simply make a module like so:

      defmodule MyProducer do
        use Kafee.Producer
      end

  At which point you will be able to do this:

      iex> :ok = MyProducer.produce([%Kafee.Producer.Message{
      ...> key: "key",
      ...> value: "value",
      ...> topic: "my-topic"
      ...> }])

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

      iex> :ok = MyProducer.publish(:order_created, %Order{})

  ## Testing

  Kafee includes a `Kafee.Producer.TestBackend` to help test if messages
  were sent in your code. See `Kafee.Producer.TestBackend` and
  `Kafee.Testing` for more information.

  ## Telemetry Events

  - `[:kafee, :produce, :start]` - Starting to send a message to Kafka.
  - `[:kafee, :produce, :stop]` - Kafka acknowledged the message.
  - `[:kafee, :produce, :exception]` - An exception occurred sending a message to Kafka.

  These events will be emitted for the async backend, and sync backend, but
  _not_ the test backend. Each will include the topic and partition of the
  message being sent, as well as the count if you are using the async backend.

  The recommended collection of these metrics can be done via:

      summary("kafee.produce.stop.count",
        tags: [:topic, :partition]
      ),
      summary("kafee.produce.stop.duration",
        tags: [:topic, :partition],
        unit: {:native, :millisecond}
      ),
      summary("kafee.produce.exception.duration",
        tags: [:topic, :partition],
        unit: {:native, :millisecond}
      )

  """

  require OpenTelemetry.Tracer, as: Tracer

  alias Kafee.Producer.{Config, Message, ValidationError}

  @data_streams_propagator_key Datadog.DataStreams.Propagator.propagation_key()

  @doc false
  defmacro __using__(module_opts \\ []) do
    quote do
      use Supervisor

      @doc false
      @impl Supervisor
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
          {Kafee.Producer.Config, config}
        ]

        child_spec = config.producer_backend.child_spec([config])

        children =
          if is_nil(child_spec),
            do: children,
            else: Enum.reverse([child_spec | children])

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
      @spec produce(Kafee.Producer.Message.t() | [Kafee.Producer.Message.t()]) :: :ok | {:error, term()}
      def produce(message) when is_map(message) do
        produce([message])
      end

      @doc """
      Sends a list of messages to the configured backend to be
      sent to Kafka. See `Kafee.Producer.normalize/2` and
      `Kafee.Producer.produce/2` functions for more information.
      """
      def produce(messages) do
        messages
        |> Kafee.Producer.normalize(__MODULE__)
        |> Kafee.Producer.validate_batch!()
        |> Kafee.Producer.annotate_batch()
        |> Kafee.Producer.produce(__MODULE__)
      end
    end
  end

  @doc """
  Normalizes a list of messages by partitioning them and setting
  producer default values. This is the last step before sending them
  the backend and eventually Kafka.

  ## Examples

      iex> normalize([%Kafee.Producer.Message{key: "test", partition: nil, topic: "test"}], MyProducer)
      [%Kafee.Producer.Message{key: "test", partition: 0, partition_fun: :random, topic: "test"}]

  """
  @spec normalize([Message.t()], atom()) :: [Message.t()]
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

      iex> validate_batch!([%Kafee.Producer.Message{topic: "test", partition: 1}])
      [%Kafee.Producer.Message{topic: "test", partition: 1}]

  """
  @spec validate_batch!([Message.t()]) :: [Message.t()]
  def validate_batch!(messages) do
    Enum.map(messages, fn message -> validate!(message) end)
  end

  @doc """
  Validates messages to ensure they have a topic and partition before
  sending them into a queue. This is designed to error early and
  in-line before it gets to a queue, where the problem would be much,
  _much_ bigger.

      iex> validate!(%Kafee.Producer.Message{topic: nil, partition: 0})
      ** (Kafee.Producer.ValidationError) Message is missing a topic to send to.

      iex> validate!(%Kafee.Producer.Message{topic: "", partition: nil})
      ** (Kafee.Producer.ValidationError) Message is missing a partition to send to.

      iex> validate!(%Kafee.Producer.Message{topic: "", partition: 0, headers: [{"test", nil}]})
      ** (Kafee.Producer.ValidationError) Message header keys and values must be a binary value.

      iex> validate!(%Kafee.Producer.Message{topic: "", partition: 0, headers: []})
      %Kafee.Producer.Message{topic: "", partition: 0, headers: []}

  """
  @spec validate!(Message.t()) :: Message.t()
  def validate!(%Message{topic: nil} = message),
    do: raise(ValidationError, kafee_message: message, validation_error: :topic)

  def validate!(%Message{partition: nil} = message),
    do: raise(ValidationError, kafee_message: message, validation_error: :partition)

  def validate!(%Message{} = message) do
    for {key, value} <- message.headers do
      if not (is_binary(key) and is_binary(value)) do
        raise(ValidationError, kafee_message: message, validation_error: :headers)
      end
    end

    message
  end

  @doc """
  Annotates a list of messages with tracking. See `annotate/1` for more
  information.
  """
  @spec annotate_batch([Message.t()]) :: [Message.t()]
  def annotate_batch(messages) do
    Enum.map(messages, &annotate/1)
  end

  @doc """
  Annotations a message with tracking. Currently this only integrates the
  `Datadog.DataStreams.Integrations.Kafka` module.
  """
  @spec annotate(Message.t()) :: Message.t()
  def annotate(%Message{} = message) do
    already_includes_header? =
      Enum.find(message.headers, fn {key, _} ->
        key == @data_streams_propagator_key
      end)

    if already_includes_header? do
      message
    else
      Datadog.DataStreams.Integrations.Kafka.trace_produce(message)
    end
  end

  @doc """
  Produces a list of messages depending on the configuration set
  in the producer.

  ## Examples

      iex> produce([%Kafee.Producer.Message{topic: "test"}], MyProducer)
      :ok

  """
  @spec produce([Message.t()], atom) :: :ok | {:error, term()}
  def produce(messages, producer) do
    config = Config.get(producer)
    {span_name, span_attributes} = otel_values(messages, config)

    Tracer.with_span span_name, span_attributes do
      config.producer_backend.produce(config, messages)
    end
  end

  # These values come from the official opentelemetry specification about messaging
  # and Kafka handling. For more information, view this link:
  # https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/semantic_conventions/messaging.md
  @spec otel_values([Message.t()], Config.t()) :: {String.t(), map()}
  defp otel_values([message | _] = messages, config) do
    # Ideally the topic will be validated above before producing, but
    # we want to be double safe.
    span_name = if is_nil(message.topic), do: "publish", else: message.topic <> " publish"

    {span_name,
     %{
       kind: :client,
       attributes: %{
         "messaging.batch.message_count": length(messages),
         "messaging.destination.kind": "topic",
         "messaging.destination.name": message.topic,
         "messaging.operation": "publish",
         "messaging.system": "kafka",
         "network.transport": "tcp",
         "peer.service": "kafka",
         "server.address": config.hostname,
         "server.socket.port": config.port
       }
     }}
  end
end
