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
      Sends a list of messages to the configured backend to be
      sent to Kafka. See `Kafee.Producer.normalize/2` and
      `Kafee.Producer.produce/2` functions for more information.
      """
      @spec produce([Kafka.Producer.Message.t()]) :: :ok | {:error, term()}
      def produce(messages) do
        messages
        |> Kafee.Producer.normalize(__MODULE__)
        |> Kafee.Producer.validate!()
        |> Kafee.Producer.produce(__MODULE__)
      end
    end
  end

  @doc """
  Normalizes a list of messages by partitioning them and
  validating them. This is the last step before sending them
  the backend and eventually Kafka.

  ## Examples

      iex> normalize([%Message{}], MyProducer)
      [%Message{}]

  """
  @spec normalize([Message.t()], atom()) :: [Message.t()]
  def normalize(messages, producer) do
    config = Config.get(producer)

    Enum.map(messages, fn message ->
      message =
        message
        |> map_put_new_if_nil(:topic, config.topic)
        |> map_put_new_if_nil(:partition_fun, config.partition_fun)

      case Map.get(message, :partition, nil) do
        int when is_integer(int) ->
          message

        nil ->
          {:ok, partition} = config.producer_backend.partition(config, message)
          Map.put(message, :partition, partition)
      end
    end)
  end

  # Fun fact, the `Map.put_new` only works if the key is missing.
  # Since we are doing this on a struct, the key will always exist,
  # so we have this fun function to help us.
  defp map_put_new_if_nil(map, key, value) do
    case Map.get(map, key, nil) do
      nil -> Map.put(map, key, value)
      _ -> map
    end
  end

  @doc """
  Validates messages to ensure they have a topic and partition before
  sending them into a queue. This is designed to error early and
  in-line before it gets to a queue, where the problem would be much,
  _much_ bigger.

  ## Examples

      iex> validate!(%Message{topic: "test", partition: 1})
      %Message{topic: "test", partition: 1}

  """
  @spec validate!(list(Message.t()) | Message.t()) :: Message.t()
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

  def validate!(messages) do
    for message <- messages do
      validate!(message)
    end
  end

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
