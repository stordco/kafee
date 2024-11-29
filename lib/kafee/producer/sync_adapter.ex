defmodule Kafee.Producer.SyncAdapter do
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
                    ]
                  )

  # credo:disable-for-lines:8 /\.Readability\./
  @moduledoc """
  This is an synchronous adapter for sending messages to Kafka.
  This will block the process until acknowledgement from Kafka
  before continuing. See `:brod.produce_sync_offset/5` for more details.

  ## Options

  #{NimbleOptions.docs(@options_schema)}
  """

  @behaviour Kafee.Producer.Adapter
  @behaviour Supervisor

  import Kafee, only: [is_offset: 1]

  require OpenTelemetry.Tracer, as: Tracer

  alias Datadog.DataStreams.Integrations.Kafka, as: DDKafka
  alias Kafee.Producer.Message

  @doc false
  @impl Kafee.Producer.Adapter
  @spec start_link(module(), Kafee.Producer.options()) :: Supervisor.on_start()
  def start_link(producer, options) do
    Kafee.BrodSupervisor.start_link(producer, options)
  end

  @doc false
  def start_brod_client(producer, options) do
    Supervisor.start_link(__MODULE__, {producer, options})
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
  Calls the `:brod.produce_sync/5` function.
  """
  @impl Kafee.Producer.Adapter
  @spec produce([Message.input()], module(), Kafee.Producer.options()) :: :ok | {:error, term()}
  def produce(messages, producer, options) do
    for message <- messages do
      message =
        message
        |> Message.set_module_values(producer, options)
        |> Message.encode(producer, options)
        |> Message.partition(producer, options)
        |> Message.set_request_id_from_logger()
        |> Message.validate!()

      span_name = Message.get_otel_span_name(message)
      span_attributes = Message.get_otel_span_attributes(message)

      Tracer.with_span span_name, %{kind: :client, attributes: span_attributes} do
        message = Datadog.DataStreams.Integrations.Kafka.trace_produce(message)

        :telemetry.span([:kafee, :produce], %{topic: message.topic, partition: message.partition}, fn ->
          # We pattern match here because it will cause `:telemetry.span/3` to measure exceptions
          {:ok, offset} =
            :brod.produce_sync_offset(brod_client(producer), message.topic, message.partition, :undefined, [
              %{
                key: message.key,
                value: message.value,
                headers: message.headers
              }
            ])

          if is_offset(offset), do: DDKafka.track_produce(message.topic, message.partition, offset)

          {:ok, %{}}
        end)
      end
    end

    :ok
  rescue
    e in Message.ValidationError -> {:error, e}
    e in MatchError -> e.term
  end

  @spec brod_client(module()) :: module()
  defp brod_client(producer) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(producer, "BrodClient")
  end
end
