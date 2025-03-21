defmodule Kafee.Producer do
  @options_schema NimbleOptions.new!(
                    adapter: [
                      default: nil,
                      doc: """
                      A module implementing `Kafee.Producer.Adapter`. This module is
                      responsible for the actual sending of messages to Kafka via
                      various lower level libraries and strategies.

                      If you set this value to `nil`, no messages will ever be sent
                      to Kafka. This is useful in development mode where you do not
                      care about messages being sent, or you do not have a Kafka
                      instance to connect to.

                      If you are in a testing environment, and want to test that
                      messages are being produced without the need for mocking,
                      you can use the `Kafee.Producer.TestAdapter`.

                      See individual producer adapter modules for more options.
                      """,
                      required: true,
                      type: {:or, [nil, :atom, :mod_arg]}
                    ],
                    encoder: [
                      default: nil,
                      doc: """
                      A module implementing `Kafee.EncoderDecoder`. This module will
                      automatically encode the Kafka message from a native Elixir
                      data type to a binary type for the Kafka message value.

                      If you set this value to `nil`, no message value will be
                      encoded. The message value will need to be a binary value.

                      Kafee has built in support for Jason and Protobuf encoding. See
                      individual encoder decoder modules for more options.
                      """,
                      type: {:or, [nil, :atom, :mod_arg]}
                    ],
                    host: [
                      default: "localhost",
                      doc: """
                      Kafka bootstrap server to connect to for sending messages.
                      """,
                      type: :string
                    ],
                    port: [
                      default: 9092,
                      doc: """
                      Kafka bootstrap server port to connect to for sending messages.
                      """,
                      type: :non_neg_integer
                    ],
                    sasl: [
                      doc: """
                      A tuple for SASL authentication to the Kafka cluster. This can
                      be `:plain`, `:scram_sha_256`, or `:scram_sha_512`, and a username
                      and password. For example, to use plain username and password
                      authentication you'd set this to `{:plain, "username", "password"}`.
                      """,
                      type: {:tuple, [:atom, :string, :string]}
                    ],
                    ssl: [
                      default: false,
                      doc: """
                      Enable SSL for communication with the Kafka cluster
                      """,
                      type: :boolean
                    ],
                    topic: [
                      doc: """
                      The Kafka topic to send messages to.
                      """,
                      required: true,
                      type: :string,
                      type_doc: "`Kafee.topic()`"
                    ],
                    partition_fun: [
                      default: :hash,
                      doc: """
                      The default partition function for all messages sent via
                      this module.

                      This value can be set as `:hash`, `:random`, or a custom
                      function like so:

                          fn topic, partitions, key, value -> 2 end

                      """,
                      required: true,
                      type: {:or, [:atom, {:fun, 4}]},
                      type_doc: "`Kafee.partition_fun()`"
                    ],
                    client_id: [
                      doc: """
                      A custom client id to use for the Kafka producer.

                      By default it will use the name of the module.

                      This is useful when observing the stream lineage.
                      """,
                      required: false,
                      type: :string
                    ]
                  )

  # credo:disable-for-lines:7 /\.Readability\./
  @moduledoc """
  A module based Kafka producer with pluggable adapters allowing for
  asynchronous, synchronous, and no-op sending of messages to Kafka.

  ## Options

  #{NimbleOptions.docs(@options_schema)}

  ## Using

  To get started simply make a module like so:

      defmodule MyProducer do
        use Kafee.Producer,
          topic: "my-topic",
          partition_fun: :random
      end

  At which point you will be able to do this:

      iex> :ok = MyProducer.produce(%Kafee.Producer.Message{
      ...>   key: "key",
      ...>   value: "value",
      ...>   partition: 1
      ...> })

  Though we don't recommend calling `produce/1` directly in your code.
  Instead, you should add some function heads to your module to handle
  transformation and partitioning.

      defmodule MyProducer do
        use Kafee.Producer,
          topic: "my-topic",
          partition_fun: :random

        def publish(:order_created, %Order{} = order)
          produce(%Kafee.Producer.Message{
            key: order.tenant_id,
            value: Jason.encode!(order),
            partition: 1
          })
        end
      end

  Then just safely call the `publish/2` function in your application.

      iex> :ok = MyProducer.publish(:order_created, %Order{})

  ### Automatic encoding

  We also support using `Kafee.EncoderDecoder` to automatically encode
  the message value before publishing. This can make your code cleaner
  as well as ensure common practices are enforced (like setting the
  `content-type` header.) To enable this, you'll need to set the
  `encoder` option like so:

      defmodule MyProducer do
        use Kafee.Producer,
          encoder: Kafee.JasonEncoderDecoder,
          topic: "order-created",
          partition_fun: :random

        def publish(:order_created, %Order{} = order)
          produce(%Kafee.Producer.Message{
            key: order.tenant_id,
            value: order
          })
        end
      end

  ## Testing

  Kafee includes a `Kafee.Producer.TestAdapter` to help test if messages
  were sent in your code. See `Kafee.Producer.TestAdapter` and
  `Kafee.Testing` for more information.

  > #### OTP 26+ {: .info}
  >
  > If you are using OTP 26 or later, maps are no longer sorted in a consistent
  > way. This means if you are testing JSON formatted messages, there is a good
  > chance the keys will be out of order resulting in flakey tests. We strongly
  > recommend using [an encoder decoder module](#automatic-encoding) to work
  > with native types. More info available in the `Kafee.Producer.TestAdapter`
  > module.

  ## Telemetry Events

  - `[:kafee, :produce, :start]` - Starting to send a message to Kafka.
  - `[:kafee, :produce, :stop]` - Kafka acknowledged the message.
  - `[:kafee, :produce, :exception]` - An exception occurred sending a message to Kafka.

  These events will be emitted for the async adapter, and sync adapter, but
  _not_ the test adapter. Each will include the topic and partition of the
  message being sent, as well as the count if you are using the async adapter.

  The recommended collection of these metrics can be done via:

      counter("kafee.produce.start.count",
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

  @typedoc "All available options for a Kafee.Producer module"
  @type options() :: [unquote(NimbleOptions.option_typespec(@options_schema))]

  @doc false
  defmacro __using__(opts \\ []) do
    quote location: :keep, bind_quoted: [opts: opts, module: __CALLER__.module] do
      @doc false
      @spec child_spec(Kafee.Producer.options()) :: Supervisor.child_spec()
      def child_spec(args) do
        full_opts = Keyword.merge(unquote(Macro.escape(opts)), args)

        %{
          id: Keyword.get(full_opts, :client_id, inspect(__MODULE__)),
          start: {Kafee.Producer, :start_link, [__MODULE__, full_opts]}
        }
      end

      @doc """
      Sends a single message to the configured adapter to be
      sent to Kafka.
      """
      @spec produce(Kafee.Producer.Message.input() | [Kafee.Producer.Message.input()]) :: :ok | {:error, term()}
      def produce(%Kafee.Producer.Message{} = message) do
        Kafee.Producer.produce(__MODULE__, [message])
      end

      @doc """
      Sends a list of messages to the configured adapter to be
      sent to Kafka.
      """
      def produce(messages) do
        Kafee.Producer.produce(__MODULE__, messages)
      end
    end
  end

  @doc """
  Starts a Kafee producer module with the given options. These options
  are validated and then passed to the configured adapter, which is
  responsible for starting the whole process tree.
  """
  @spec start_link(module(), options()) :: Supervisor.on_start()
  def start_link(producer, options) do
    with {:ok, options} <- NimbleOptions.validate(options, @options_schema) do
      :ets.insert(:kafee_config, {producer, options})

      case Keyword.get(options, :adapter) do
        nil -> :ignore
        adapter when is_atom(adapter) -> adapter.start_link(producer, options)
        {adapter, _adapter_options} -> adapter.start_link(producer, options)
      end
    end
  end

  @doc """
  Produces a list of messages via the given `Kafee.Producer` module.
  """
  @spec produce(module(), [Kafee.Producer.Message.input()]) :: :ok | {:error, term()}
  def produce(producer, messages) do
    options = :ets.lookup_element(:kafee_config, producer, 2)

    case Keyword.get(options, :adapter, nil) do
      nil -> :ok
      adapter when is_atom(adapter) -> adapter.produce(messages, producer, options)
      {adapter, _adapter_opts} -> adapter.produce(messages, producer, options)
    end
  rescue
    _e in ArgumentError -> {:error, :producer_not_found}
  end
end
