defmodule Kafee.Consumer.BrodBackend do
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

  # credo:disable-for-lines:11 /\.Readability\./
  @moduledoc """
  A Kafee consumer backend based on `:brod_group_subscriber_v2`.
  This will start a single process for each partition to process
  messages, but unlike the `Kafee.Consumer.BroadwayBackend`, this
  will wait until the message is processed before acknowledging.
  This also guarantees message processing order at the expense
  of throughput.

  ## Options

  #{NimbleOptions.docs(@options_schema)}
  """

  @behaviour Kafee.Consumer.Backend
  @behaviour Supervisor

  require Logger

  @typedoc "All available options for a Kafee.Consumer.BroadwayBackend module"
  @type options() :: [unquote(NimbleOptions.option_typespec(@options_schema))]

  @doc false
  @impl Kafee.Consumer.Backend
  @spec start_link(module(), Kafee.Consumer.options()) :: Supervisor.on_start()
  def start_link(module, options) do
    Supervisor.start_link(__MODULE__, {module, options})
  end

  @doc false
  @spec child_spec({module(), Kafee.Consumer.options()}) :: :supervisor.child_spec()
  def child_spec({module, options}) do
    default = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [{module, options}]},
      type: :supervisor
    }

    Supervisor.child_spec(default, [])
  end

  @doc false
  @impl Supervisor
  def init({module, options}) do
    {_, backend_options} = options[:backend]

    with {:ok, backend_options} <- NimbleOptions.validate(backend_options, @options_schema) do
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      brod_client = Module.concat(module, "BrodClient")

      children = [
        %{
          id: brod_client,
          start:
            {:brod_client, :start_link,
             [
               [{options[:host], options[:port]}],
               brod_client,
               client_config(options, backend_options)
             ]},
          type: :worker,
          restart: :permanent,
          shutdown: 500
        },
        %{
          id: module,
          start:
            {:brod_group_subscriber_v2, :start_link,
             [
               %{
                 client: brod_client,
                 group_id: options[:consumer_group_id],
                 topics: [options[:topic]],
                 cb_module: Kafee.Consumer.BrodWorker,
                 message_type: :message,
                 init_data: %{
                   consumer_group: options[:consumer_group_id],
                   module: module
                 }
               }
             ]},
          type: :worker,
          restart: :permanent,
          # We set the brod subscriber to infinity shutdown to allow
          # any messages to finish processing. This matches the
          # broadway setup.
          shutdown: :infinity
        }
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  defp client_config(options, backend_options) do
    (options ++ backend_options)
    |> Keyword.take([:connect_timeout, :max_retries, :retry_backoff_ms, :sasl, :ssl])
    |> Keyword.reject(fn {_k, v} -> is_nil(v) end)
  end
end
