defmodule Kafee.Consumer do
  @options_schema NimbleOptions.new!(
                    backend: [
                      default: nil,
                      doc: """
                      A module implementing `Kafee.Consumer.Backend`. This module is responsible for
                      the actual fetching and processing of Kafka messages allowing easy switching
                      with minimal code changes.

                      If you set this value to `nil` (default), no backend will start and no messages
                      will be processed. This is useful to set in testing or development environments
                      where you do not have a Kafka server available but don't want to adjust your
                      supervisor tree.

                      See individual backend modules for more options.
                      """,
                      required: true,
                      type: {:or, [nil, :mod_arg]}
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
                      type: {:tuple, [:string]}
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
          backend: {Kafee.Consumer.BroadwayBackend, [
            host: "localhost",
            port: 1234
          ]}

        def handle_message(%Kafee.Consumer.Message{} = message) do
          # Do some logic
          :ok
        end
      end

  This is the most basic form of a consumer. Once it's in your application
  supervisor tree, it will start all of the processes needed to handle Kafka
  messages.

  ### Without a backend

  The `Kafee.Consumer` module also accepts no `backend` option. This will
  disable the consumer from processing any messages. We recommend using this
  as the default backend so a Kafka server is not required in development
  or testing environments. A full setup would look something like this:

      defmodule MyConsumer do
        use Kafee.Consumer,
          backend: Application.compile_env(:my_app, :kafee_consumer_backend, nil)

        # message handling code
      end

  This will avoid your consumer from starting in any environment. So now
  you can add some configuration in your `config/prod.exs` file to start
  the consumer when in production:

      config :my_app, :kafee_consumer_backend, {Kafee.Consumer.BroadwayBackend, [
        host: "localhost",
        port: 1234
      ]}

  ## Error Handling

  Error handling will (or will not) be reported differently to Kafka
  depending on what backend you are using. However, there is an optional
  `handle_failure/2` callback that can be implemented. This will be called
  when ever the `handle_message/1` function raises an error.

  This is where you should implement any sort of reporting, or dead letter
  queue logic.

        defmodule MyConsumer do
          # setup and message handling code

          def handle_failure({:error, %Ecto.Changeset{} = changeset}, message) do
            # Here we hit an Ecto changeset error while processing a message.
          end

          def handle_failure(%RuntimeError{} = error, message) do
            # And here was a runtime failure we need to handle.
          end
        end

  Keep in mind that Kafee will already do basic error tracking (as mentioned
  in the next section.) You do not _need_ to emit custom telemetry or set
  Open Telemetry trace data.

  ## Telemetry
  """

  require OpenTelemetry.Tracer, as: Tracer

  @typedoc "All available options for a Kafee.Consumer module"
  @type options() :: unquote(NimbleOptions.option_typespec(@options_schema))

  @doc "Handles a single message from Kafka"
  @callback handle_message(Kafee.Consumer.Message.t()) :: :ok

  @doc "Handles an error while processing a Kafka message"
  @callback handle_failure(any(), Kafee.Consumer.Message.t()) :: :ok

  @optional_callbacks handle_failure: 2

  @doc false
  defmacro __using__(opts \\ []) do
    quote location: :keep, bind_quoted: [opts: opts, module: __CALLER__.module] do
      @behaviour Kafee.Consumer

      unless Module.has_attribute?(__MODULE__, :moduledoc) do
        @moduledoc """
        Processing messages from Kafka.
        """
      end

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
      def handle_failure(error, %Kafee.Consumer.Message{} = message) do
        inspected_message = inspect(message)
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
  validated and then passed to the configured backend, which is responsible
  for starting the whole process tree.
  """
  @spec start_link(module(), Keyword.t()) :: Supervisor.on_start()
  def start_link(module, options) do
    with {:ok, options} <- NimbleOptions.validate(options, @options_schema),
         {backend, backend_options} <- options[:backend] do
      backend.start_link(module, options, backend_options)
    else
      nil -> :ignore
      {:error, validation_error} -> {:error, validation_error}
    end
  end

  @doc """
  Pushes a list of messages to the consumer. See `push_message/2` for
  more details.
  """
  @spec push_messages(module(), [Kafee.Consumer.Message.t()]) :: :ok
  def push_messages(consumer, messages),
    do: Enum.each(messages, &push_message(consumer, &1))

  @doc """
  Sends a message to the consumer for processing. This also wraps up
  the error handling, open telemetry tracing, and data streams tracking.
  """
  @spec push_message(module(), Kafee.Consumer.Message.t()) :: :ok
  def push_message(consumer, %Kafee.Consumer.Message{} = message) do
    set_logger_request_id(message)

    {span_name, span_attributes} = get_otel_tracer_data(message)

    Tracer.with_span span_name, span_attributes do
      Datadog.DataStreams.Integrations.Kafka.trace_consume(message, message.consumer_group)

      Datadog.DataStreams.Integrations.Kafka.track_consume(
        message.consumer_group,
        message.topic,
        message.partition,
        message.offset
      )

      consumer.handle_message(message)
    end

    :ok
  rescue
    error ->
      consumer.handle_failure(error, message)
      :ok
  end

  # These values are taken from the OTEL 1.25.0 trace spec for messaging systems
  # https://opentelemetry.io/docs/specs/otel/trace/semantic_conventions/messaging/
  @spec get_otel_tracer_data(Kafee.Consumer.Message.t()) :: {String.t(), map()}
  defp get_otel_tracer_data(message) do
    span_name = if is_nil(message.topic), do: "consume", else: message.topic <> " consume"

    attributes =
      maybe_put_otel_conversation_id(
        %{
          "messaging.system": "kafka",
          "messaging.operation": "process",
          "messaging.source.name": message.topic,
          "messaging.kafka.message.key": message.key,
          "messaging.kafka.consumer.group": message.consumer_group,
          "messaging.kafka.source.partition": message.partition,
          "messaging.kafka.message.offset": message.offset
        },
        message
      )

    {span_name, %{kind: :client, attributes: attributes}}
  end

  @spec maybe_put_otel_conversation_id(map(), Kafee.Consumer.Message.t()) :: map()
  defp maybe_put_otel_conversation_id(attributes, message) do
    if request_id = get_request_id(message) do
      Map.put(attributes, :"messaging.message.conversation_id", request_id)
    else
      attributes
    end
  end

  @spec set_logger_request_id(Kafee.Consumer.Message.t()) :: no_return()
  defp set_logger_request_id(message) do
    if request_id = get_request_id(message) do
      Logger.metadata(request_id: request_id)
    else
      Logger.metadata(request_id: nil)
    end
  end

  @spec get_request_id(Kafee.Consumer.Message.t()) :: nil | String.t()
  defp get_request_id(message) do
    case Enum.find(message.headers, fn {k, _v} -> k === "kafka_correlationId" end) do
      nil -> nil
      {"kafka_correlationId", request_id} -> request_id
    end
  end
end
