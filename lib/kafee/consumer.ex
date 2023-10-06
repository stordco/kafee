defmodule Kafee.Consumer do
  @options_schema NimbleOptions.new!([
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
    ]
  ])

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

      @doc false
      @spec child_spec(__MODULE__.options()) :: Supervisor.child_spec()
      def child_spec(args) do
        full_opts = Keyword.merge(unquote(Macro.escape(opts)), args)
        __MODULE__.start_link(unquote(module), full_opts)
      end

      @impl Kafee.Consumer
      def handle_message(%Kafee.Consumer.Message{}) do
        raise RuntimeError,
          message: """
          No `handle_message/1` function has been defined in `#{__MODULE__}`.
          """
      end

      @impl Kafee.Consumer
      def handle_failure(error, %Kafee.Consumer.Message{} = message) do
        raise RuntimeError,
          message: """
          An error has been raised while processing a Kafka message.

          Message:
          #{message}

          Error:
          #{error}
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
  @spec start_link(module(), options) :: Supervisor.start_link()
  def start_link(module, options) do
    options = NimbleOptions.validate!(options, @options_schema)

    case options.backend do
      nil -> :ignore
      {backend, _backend_options} -> backend.start_link(module, options)
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
    {span_name, span_attributes} = otel_values(message)

    Tracer.with_span span_name, span_attributes do
      Datadog.DataStreams.Integrations.Kafka.trace_consume(message, message.consumer_group)
      consumer.handle_message(message)
    end

    :ok
  rescue
    e ->
      consumer.handle_failure(e, message)
      :ok
  end

  defp otel_values(message) do
    span_name = if is_nil(message.topic), do: "consume", else: message.topic <> " consume"

    {span_name, %{
      kind: :client,
      attributes: %{

      }
    }}
  end
end
