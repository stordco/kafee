defmodule Kafee.Consumer.BroadwayAdapter do
  @batching_default_options [
    concurrency: System.schedulers_online() * 2,
    batch_size: 1
  ]
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
                    consumer_concurrency: [
                      default: 4,
                      doc: """
                      The number of Kafka consumers to run in parallel. In total (all nodes running)
                      this number should be larger than the total number of Kafka partitions. This
                      ensures every Kafka partition will have its own individual consumer, ensuring
                      higher throughput.
                      """,
                      type: :non_neg_integer
                    ],
                    processor_concurrency: [
                      doc: """
                      The number of Elixir processes to run to process the Kafka messages. See
                      the Broadway documentation for more details. By default, this is the
                      Broadway default, which is `System.schedulers_online() * 2`.
                      """,
                      type: :non_neg_integer
                    ],
                    batching: [
                      required: false,
                      doc: """
                      Optional.
                      Options for `batches` configuration in Broadway.

                      See its [documentation](https://hexdocs.pm/broadway/Broadway.html#module-the-default-batcher).

                      ## Notes
                      1. Batching is _always turned on_, with a size of 1.
                      2. Only the `:default` batcher key is supported.
                      3. On top of this, there's an optional `async_run` option,
                         where it will run `Kafee.Consumer.Adapter.push_message` asynchronously across all messages in that batch.

                      """,
                      type: :non_empty_keyword_list,
                      keys: [
                        concurrency: [
                          required: true,
                          type: :non_neg_integer,
                          doc: """
                          Set concurrency for batches.
                          Note that typically due to the limitation of Kafka a single processes will be assigned per partition.
                          For example, for a 12 partition topic, assigning 50 concurrent batches to run will only end up
                          using around 12 processes. Rest of the concurrency capacity will be not used.

                          Default is System.schedulers_online() * 2, which is recommended by BroadwayKafka.
                          """
                        ],
                        size: [
                          required: true,
                          type: :non_neg_integer,
                          doc: """
                          Max number of messages to have per batch.

                          Default size is 1.
                          """
                        ],
                        timeout: [
                          default: 1_000,
                          type: :non_neg_integer,
                          doc: """
                          Max time allowed to wait for adding messages into batch until batch starts processing.
                          """
                        ],
                        async_run: [
                          default: false,
                          type: :boolean,
                          doc: """
                          Flag that decides batch processing will be done asynchronously.
                          The async operations run through Task.await_many/2 with an infinity timeout.
                          """
                        ]
                      ]
                    ]
                  )

  # credo:disable-for-lines:10 /\.Readability\./
  @moduledoc """
  A Kafee consumer adapter based on the exceptional `Broadway` library.
  This adatper is made for maximum freight train throughput with no
  stopping. **All messages are acknowledged immediately** after being
  received. This means that you are responsible for creating some logic
  to handle failed messages, **or they will be dropped**.

  ## Options

  #{NimbleOptions.docs(@options_schema)}

  ## Note that batching is always turned on
  To simplify the options and logic paths on the configuration, we took a pragmatic approach.

  [Batching](https://hexdocs.pm/broadway_kafka/BroadwayKafka.Producer.html#module-concurrency-and-partitioning)
  is always turned on, and default size will be 1 unless increased.

  """

  @behaviour Broadway
  @behaviour Kafee.Consumer.Adapter

  require Logger

  @typedoc "All available options for a Kafee.Consumer.BroadwayAdapter module"
  @type options() :: [unquote(NimbleOptions.option_typespec(@options_schema))]

  @doc false
  @impl Kafee.Consumer.Adapter
  @spec start_link(module(), Kafee.Consumer.options()) :: Supervisor.on_start()
  def start_link(consumer, options) do
    with {:ok, adapter_options} <- validate_adapter_options(options) do
      Broadway.start_link(
        __MODULE__,
        broadway_config(consumer, options, adapter_options)
      )
    end
  end

  defp validate_adapter_options(options) do
    adapter_options =
      case options[:adapter] do
        nil -> []
        adapter when is_atom(adapter) -> []
        {_adapter, adapter_options} -> adapter_options
      end

    NimbleOptions.validate(adapter_options, @options_schema)
  end

  defp broadway_config(consumer, options, adapter_options) do
    base_config = [
      name: consumer,
      context: %{
        consumer: consumer,
        consumer_group: options[:consumer_group_id],
        options: options,
        adapter_options: adapter_options
      },
      producer: [
        module:
          {BroadwayKafka.Producer,
           [
             hosts: [{options[:host], options[:port]}],
             group_id: options[:consumer_group_id],
             topics: [options[:topic]],
             client_config: client_config(options)
           ]},
        concurrency: adapter_options[:consumer_concurrency]
      ],
      processors: [
        default: [
          concurrency: processor_concurrency(adapter_options)
        ]
      ]
    ]

    case Keyword.fetch(adapter_options, :batching) do
      {:ok, batching} ->
        Keyword.merge(base_config,
          batchers: [
            default: [
              concurrency: batching[:concurrency],
              batch_size: batching[:size],
              batch_timeout: batching[:timeout]
            ]
          ]
        )

      :error ->
        Keyword.merge(base_config,
          batchers: [
            default: @batching_default_options
          ]
        )
    end
  end

  defp client_config(options) do
    options
    |> Keyword.take([:connect_timeout, :sasl, :ssl])
    |> Keyword.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp processor_concurrency(adapter_options),
    do: Keyword.get(adapter_options, :processor_concurrency, System.schedulers_online() * 2)

  @doc false
  @impl Broadway
  def handle_message(:default, %Broadway.Message{} = message, _context) do
    message
  end

  @impl Broadway
  def handle_batch(
        :default,
        messages,
        _batch_info,
        %{
          adapter_options: adapter_options,
          consumer: consumer,
          options: options
        } = _context
      ) do
    batch_config = adapter_options[:batching]

    if batch_config[:async_run] do
      # No need for Task.Supervisor as it is not running under a GenServer,
      # and Kafee.Consumer.Adapter.push_message does already have error handling.
      tasks = Enum.map(messages, &Task.async(fn -> do_consumer_work(&1, consumer, options) end))
      Task.await_many(tasks, :infinity)
    else
      Enum.map(messages, fn message -> do_consumer_work(message, consumer, options) end)
    end
  catch
    kind, reason ->
      Logger.error(
        "Caught #{kind} attempting to handle batch : #{Exception.format(kind, reason, __STACKTRACE__)}",
        kind: kind,
        reason: reason,
        consumer: consumer,
        messages: messages
      )

      # If we catch at this stage we have no way of knowing which messages successfully processed
      # So we will mark all messages as failed.
      Enum.map(messages, &Broadway.Message.failed(&1, reason))
  end

  defp do_consumer_work(
         %Broadway.Message{
           data: value,
           metadata: metadata
         } = message,
         consumer,
         options
       ) do
    result =
      Kafee.Consumer.Adapter.push_message(
        consumer,
        options,
        %Kafee.Consumer.Message{
          key: metadata.key,
          value: value,
          topic: metadata.topic,
          partition: metadata.partition,
          offset: metadata.offset,
          consumer_group: options[:consumer_group_id],
          timestamp: DateTime.from_unix!(metadata.ts, :millisecond),
          headers: metadata.headers
        }
      )

    with :ok <- result do
      message
    else
      error ->
        Broadway.Message.failed(message, error)
    end
  catch
    kind, reason ->
      Logger.error("Caught #{kind} attempting to process message: #{Exception.format(kind, reason, __STACKTRACE__)}",
        kind: kind,
        reason: reason,
        consumer: consumer,
        message: message
      )

      Broadway.Message.failed(message, reason)
  end

  @doc false
  @impl Broadway
  def handle_failed(messages, %{consumer: consumer}) do
    # This error only occurs when there is an issue with the `handle_message/2`
    # function above because `Kafee.Consumer.Adapter.push_message/2` will catch any
    # errors.

    error = %RuntimeError{message: "Error converting a Broadway message to Kafee.Consumer.Message"}
    messages |> List.wrap() |> Enum.each(&consumer.handle_failure(error, &1))

    messages
  end
end
