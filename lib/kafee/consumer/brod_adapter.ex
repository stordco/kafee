defmodule Kafee.Consumer.BrodAdapter do
  @options_schema NimbleOptions.new!(
                    # Connection options
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
                    ],

                    # Mode configuration
                    mode: [
                      default: :single_message,
                      doc: """
                      Processing mode for the adapter:
                      - `:single_message` - Process one message at a time (default)
                      - `:batch` - Process messages in batches for higher throughput
                      """,
                      type: {:in, [:single_message, :batch]}
                    ],

                    # Batch configuration (only used when mode: :batch)
                    batch: [
                      required: false,
                      doc: """
                      Batch configuration options. Only used when mode is :batch.

                      Example:
                        batch: [size: 100, timeout: 2000, max_bytes: 5_000_000]
                      """,
                      type: :keyword_list
                    ],

                    # Processing configuration (only used when mode: :batch)
                    processing: [
                      required: false,
                      doc: """
                      Processing configuration for batch mode.

                      Example:
                        processing: [max_in_flight_batches: 5]
                      """,
                      type: :keyword_list
                    ],

                    # Acknowledgment configuration
                    acknowledgment: [
                      required: false,
                      doc: """
                      Acknowledgment and error handling configuration.

                      ## DLQ Configuration Options

                      ### Recommended: Using a shared DLQ producer
                      ```
                      acknowledgment: [
                        strategy: :best_effort,
                        dead_letter_producer: :my_dlq_producer,  # Name of shared producer
                        dead_letter_max_retries: 3
                      ]
                      ```

                      ### Alternative: Per-consumer DLQ topic
                      ```
                      acknowledgment: [
                        strategy: :best_effort,
                        dead_letter_topic: "my-consumer-dlq",
                        dead_letter_max_retries: 5
                      ]
                      ```

                      ## Available Options

                      - `strategy` - How to handle failures (:all_or_nothing, :best_effort, :last_successful)
                      - `dead_letter_producer` - Name of a shared Kafee.DLQProducer (recommended)
                      - `dead_letter_topic` - DLQ topic name (creates dedicated producer per consumer)
                      - `dead_letter_max_retries` - Max attempts before sending to DLQ (default: 3)
                      """,
                      type: :keyword_list
                    ]
                  )

  # credo:disable-for-lines:22 /\.Readability\./
  @moduledoc """
  A Kafee consumer adapter based on `:brod_group_subscriber_v2`.

  This adapter supports both single-message and batch processing modes:

  - **Single-message mode** (default): Processes one message at a time, waiting 
    for acknowledgment before proceeding. Guarantees message ordering within a 
    partition at the expense of throughput.
    
  - **Batch mode**: Accumulates messages into batches for improved throughput. 
    Supports various acknowledgment strategies and optional async processing 
    within batches.

  ## Configuration Examples

  ### Single-message mode (default)
  ```elixir
  adapter: {BrodAdapter, mode: :single_message}
  # or simply
  adapter: BrodAdapter
  ```

  ### Batch mode
  
  When using batch mode, you **must** implement the `handle_batch/1` callback in your consumer module:
  
  ```elixir
  defmodule MyBatchConsumer do
    use Kafee.Consumer
    
    @impl Kafee.Consumer
    def handle_batch(messages) do
      # Process batch of messages
      case MyApp.bulk_insert(messages) do
        {:ok, _} -> :ok
        {:error, failed} -> {:ok, failed}
      end
    end
  end
  ```
  
  Configuration example:
  ```elixir
  adapter: {BrodAdapter, [
    mode: :batch,
    batch: [size: 100, timeout: 2000, max_bytes: 5_000_000],
    processing: [max_in_flight_batches: 5],
    acknowledgment: [
      strategy: :best_effort,
      dead_letter_topic: "dlq",
      dead_letter_max_retries: 3
    ]
  ]}
  ```

  ## Batch Processing Features

  When using batch mode, the adapter provides:

  - Message accumulation until size, timeout, or bytes limits are reached
  - Back-pressure mechanism via max_in_flight_batches to prevent memory issues
  - Multiple acknowledgment strategies for different use cases
  - Optional Dead Letter Queue support for handling poison messages
  - Runtime validation ensuring `handle_batch/1` is implemented

  ## Options

  #{NimbleOptions.docs(@options_schema)}
  """

  @behaviour Kafee.Consumer.Adapter
  @behaviour Supervisor

  require Logger

  @typedoc """
  All available options for a Kafee.Consumer.BrodAdapter module.

  Includes connection options, batch processing configuration, and error handling settings.
  """
  @type options() :: [unquote(NimbleOptions.option_typespec(@options_schema))]

  @doc false
  @impl Kafee.Consumer.Adapter
  @spec start_link(module(), Kafee.Consumer.options()) :: Supervisor.on_start()
  def start_link(consumer, options) do
    Supervisor.start_link(__MODULE__, {consumer, options})
  end

  @doc false
  @spec child_spec({module(), Kafee.Consumer.options()}) :: :supervisor.child_spec()
  def child_spec({consumer, options}) do
    default = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [{consumer, options}]},
      type: :supervisor
    }

    Supervisor.child_spec(default, [])
  end

  @doc false
  @impl Supervisor
  def init({consumer, options}) do
    adapter_options =
      case options[:adapter] do
        nil -> []
        adapter when is_atom(adapter) -> []
        {_adapter, adapter_options} -> adapter_options
      end

    with {:ok, normalized_options} <- normalize_and_validate_options(adapter_options) do
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      brod_client = Module.concat(consumer, "BrodClient")

      # Choose appropriate worker and message type based on mode
      {cb_module, message_type} =
        case normalized_options[:mode] do
          :batch -> {Kafee.Consumer.BrodBatchWorker, :message_set}
          :single_message -> {Kafee.Consumer.BrodWorker, :message}
        end

      children = [
        %{
          id: brod_client,
          start:
            {:brod_client, :start_link,
             [
               [{options[:host], options[:port]}],
               brod_client,
               client_config(options, adapter_options)
             ]},
          type: :worker,
          restart: :permanent,
          shutdown: 500
        },
        %{
          id: consumer,
          start:
            {:brod_group_subscriber_v2, :start_link,
             [
               %{
                 client: brod_client,
                 group_id: options[:consumer_group_id],
                 topics: [options[:topic]],
                 cb_module: cb_module,
                 message_type: message_type,
                 init_data: %{
                   consumer: consumer,
                   options: options,
                   adapter_options: normalized_options
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

  defp client_config(options, adapter_options) do
    (options ++ adapter_options)
    |> Keyword.take([:connect_timeout, :max_retries, :retry_backoff_ms, :sasl, :ssl])
    |> Keyword.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp normalize_and_validate_options(opts) do
    # Validate the options first
    case NimbleOptions.validate(opts, @options_schema) do
      {:ok, _validated} ->
        # Then normalize for internal use
        {:ok, normalize_options(opts)}

      error ->
        error
    end
  end

  defp normalize_options(opts) do
    # Default to single_message mode for backward compatibility
    mode = Keyword.get(opts, :mode, :single_message)

    case mode do
      :single_message ->
        # For single message mode, just pass through relevant options
        Keyword.put(opts, :mode, :single_message)

      :batch ->
        # For batch mode, flatten the nested configurations for BrodBatchWorker
        normalize_batch_options(opts)
    end
  end

  defp normalize_batch_options(opts) do
    batch_config = Keyword.get(opts, :batch, [])
    processing_config = Keyword.get(opts, :processing, [])
    ack_config = Keyword.get(opts, :acknowledgment, [])

    # Build flattened options for BrodBatchWorker
    [
      mode: :batch,
      batch_size: Keyword.get(batch_config, :size, 100),
      batch_timeout: Keyword.get(batch_config, :timeout, 1000),
      max_batch_bytes: Keyword.get(batch_config, :max_bytes, 1_048_576),
      max_in_flight_batches: Keyword.get(processing_config, :max_in_flight_batches, 3),
      ack_strategy: Keyword.get(ack_config, :strategy, :all_or_nothing),
      connect_timeout: opts[:connect_timeout] || :timer.seconds(10),
      max_retries: opts[:max_retries] || -1,
      retry_backoff_ms: opts[:retry_backoff_ms] || 100
    ] ++ build_dlq_config(ack_config)
  end

  defp build_dlq_config(ack_config) do
    cond do
      # Shared DLQ producer (recommended)
      producer = ack_config[:dead_letter_producer] ->
        [
          dead_letter_config: [
            producer: producer,
            max_retries: ack_config[:dead_letter_max_retries] || 3
          ]
        ]

      # Per-consumer DLQ topic
      topic = ack_config[:dead_letter_topic] ->
        [
          dead_letter_config: [
            topic: topic,
            max_retries: ack_config[:dead_letter_max_retries] || 3
          ]
        ]

      # No DLQ configured
      true ->
        []
    end
  end
end
