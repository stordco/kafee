defmodule Kafee.Consumer do
  @options_schema NimbleOptions.new!(
                    adapter: [
                      default: nil,
                      doc: """
                      A module implementing `Kafee.Consumer.Adapter`. This module is responsible for
                      the actual fetching and processing of Kafka messages allowing easy switching
                      with minimal code changes.

                      If you set this value to `nil`, no adapter will start and no messages
                      will be processed. This is useful to set in testing or development environments
                      where you do not have a Kafka server available but don't want to adjust your
                      supervisor tree.

                      See individual consumer adapter modules for more options.
                      """,
                      required: true,
                      type: {:or, [nil, :atom, :mod_arg]}
                    ],
                    decoder: [
                      default: nil,
                      doc: """
                      A module implementing `Kafee.EncoderDecoder`. This module will automatically
                      decode the Kafka message value to a native Elixir type.

                      If you set this value to `nil`, no message value will be decoded. The original
                      binary string value will be processed.

                      Kafee has built in support for Jason and Protobuf encoding and decoding. See
                      individual encoder decoder modules for more options.
                      """,
                      type: {:or, [nil, :atom, :mod_arg]}
                    ],
                    host: [
                      default: "localhost",
                      doc: """
                      Kafka bootstrap server to connect to for consuming.
                      """,
                      type: :string
                    ],
                    port: [
                      default: 9092,
                      doc: """
                      Kafka bootstrap server port to connect to for consuming.
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
                    consumer_group_id: [
                      doc: """
                      The Kafka consumer group id to use when connecting. This is used
                      for process pooling among all connected clients who share the
                      same consumer group id.
                      """,
                      required: true,
                      type: :string
                    ],
                    topic: [
                      doc: """
                      The Kafka topic to process messages from.
                      """,
                      required: true,
                      type: :string
                    ]
                  )

  # credo:disable-for-lines:6 /\.Readability\./
  @moduledoc """
  A modular Kafka consumer module.

  ## Options

  #{NimbleOptions.docs(@options_schema)}

  ## Examples

  To use a `Kafee.Consumer`, you'll need to setup a module like so:

      defmodule MyConsumer do
        use Kafee.Consumer,
          adapter: Kafee.Consumer.BroadwayAdapter,
          host: "localhost",
          port: 9092

        def handle_message(%Kafee.Consumer.Message{} = message) do
          # Do some logic
          :ok
        end
      end

  This is the most basic form of a consumer. Once it's in your application
  supervisor tree, it will start all of the processes needed to handle Kafka
  messages.

  ### Without an adapter

  The `Kafee.Consumer` module also accepts no `adapter` option. This will
  disable the consumer from processing any messages. We recommend using this
  as the default adapter so a Kafka server is not required in development
  or testing environments. A full setup would look something like this:

      defmodule MyConsumer do
        use Kafee.Consumer,
          adapter: Application.compile_env(:my_app, :kafee_consumer_adapter, nil),
          host: "localhost",
          port: 9092,
          consumer_group_id: "my-app",
          topic: "my-topic"

        # message handling code
      end

  This will avoid your consumer from starting in any environment. So now
  you can add some configuration in your `config/prod.exs` file to start
  the consumer when in production:

      config :my_app, kafee_consumer_adapter: Kafee.Consumer.BroadwayAdapter

  ## Error Handling

  Error handling will (or will not) be reported differently to Kafka
  depending on what adapter you are using. However, there is an optional
  `handle_failure/2` callback that can be implemented. This will be called
  when ever the `handle_message/1` function raises an error.

  This is where you should implement any sort of reporting, or dead letter
  queue logic.

        defmodule MyConsumer do
          # setup and message handling code

          def handle_failure(%MatchError{} = error, message) do
            # Here we hit a match error while processing the message.
          end

          def handle_failure(%RuntimeError{} = error, message) do
            # And here was a runtime failure we need to handle.
          end
        end

  Keep in mind that Kafee will already do basic error tracking (as mentioned
  in the next section.) You do not need to emit custom telemetry or set
  Open Telemetry trace data.

  ## Telemetry

  This module has built in support for Open Telemetry traces based on the
  [OTEL 1.25.0 trace spec for messaging systems][otel-spec], as well as
  support for [DataDog data streams monitoring][ddd] via [data-streams-ex][dsx].
  View the documentation for Open Telemetry and DataDog data streams for
  configuration.

  As well as the mentioned above, Kafee also supports metrics via `:telemetry`.
  This exports general metrics about how many messages we are consuming and
  how long it takes to consume.

  - `[:kafee, :consume, :start]`, `[:kafee, :consume, :stop]`, and
    `[:kafee, :consume, :exception]` are all exported via a [span call][tel-span].
    These metrics include a `:module` attribute which is the Elixir module name
    that generated the metric.

  [otel-spec]: https://opentelemetry.io/docs/specs/otel/trace/semantic_conventions/messaging/
  [ddd]: https://www.datadoghq.com/product/data-streams-monitoring/
  [dsx]: https://github.com/stordco/data-streams-ex
  [tel-span]: https://hexdocs.pm/telemetry/telemetry.html#span/3
  """
  alias Kafee.Consumer.{BroadwayAdapter, BroadwaySupervisor}

  @typedoc "All available options for a Kafee.Consumer module"
  @type options() :: [unquote(NimbleOptions.option_typespec(@options_schema))]

  @doc "Handles a single message from Kafka"
  @callback handle_message(Kafee.Consumer.Message.t()) :: :ok

  @doc "Handles an error while processing a Kafka message"
  @callback handle_failure(any(), Kafee.Consumer.Message.t()) :: :ok
  # Note for BroadwayAdapater, it will always be a list of messages
  @callback handle_failure(any(), [Kafee.Consumer.Message.t()]) :: :ok

  @doc false
  defmacro __using__(opts \\ []) do
    quote location: :keep, bind_quoted: [opts: opts, module: __CALLER__.module] do
      @behaviour Kafee.Consumer

      @doc false
      @spec child_spec(Kafee.Consumer.options()) :: Supervisor.child_spec()
      def child_spec(args) do
        full_opts = Keyword.merge(unquote(Macro.escape(opts)), args)

        %{
          id: __MODULE__,
          start: {Kafee.Consumer, :start_link, [__MODULE__, full_opts]}
        }
      end

      unless Module.has_attribute?(__MODULE__, :doc) do
        @doc """
        Processing a single message from Kafka.
        """
      end

      @impl Kafee.Consumer
      def handle_message(%Kafee.Consumer.Message{}) do
        raise RuntimeError,
          message: """
          No `handle_message/1` function has been defined in `#{__MODULE__}`.
          """
      end

      unless Module.has_attribute?(__MODULE__, :doc) do
        @doc """
        Handles a failure for message processing.
        """
      end

      @impl Kafee.Consumer
      def handle_failure(error, message_or_messages) do
        inspected_message = inspect(message_or_messages)
        inspected_error = inspect(error)

        raise RuntimeError,
          message: """
          An error has been raised while processing a Kafka message.

          Message:
          #{inspected_message}

          Error:
          #{inspected_error}
          """
      end

      defoverridable child_spec: 1, handle_message: 1, handle_failure: 2
    end
  end

  @doc """
  Starts a Kafee consumer module with the given options. These options are
  validated and then passed to the configured adapter, which is responsible
  for starting the whole process tree.
  """
  @spec start_link(module(), options()) :: Supervisor.on_start()
  def start_link(consumer, options) do
    with {:ok, options} <- NimbleOptions.validate(options, @options_schema) do
      case options[:adapter] do
        nil -> :ignore
        {BroadwayAdapter, __options} -> BroadwaySupervisor.start_link(consumer, options)
        BroadwayAdapter -> BroadwaySupervisor.start_link(consumer, options)
        adapter when is_atom(adapter) -> adapter.start_link(consumer, options)
        {adapter, __options} -> adapter.start_link(consumer, options)
      end
    end
  end
end
