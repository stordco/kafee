defmodule Kafee.Consumer.BroadwayAdapter do
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
                      Options for setting `batches` in Broadway.
                      See its [documentation](https://hexdocs.pm/broadway/Broadway.html#module-the-default-batcher).

                      Also, note that only the `:default` batcher key is supported.

                      On top of this, there's an optional `async_run` option,
                      where it will run `Kafee.Consumer.Adapter.push_message` asynchronously across all messages in that batch.
                      """,
                      type: :non_empty_keyword_list,
                      keys: [
                        concurrency: [
                          required: true,
                          type: :non_neg_integer
                        ],
                        size: [
                          required: true,
                          type: :non_neg_integer
                        ],
                        timeout: [
                          default: 1_000,
                          type: :non_neg_integer
                        ],
                        async_run: [
                          default: false,
                          type: :boolean
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
  """

  @behaviour Broadway
  @behaviour Kafee.Consumer.Adapter

  require Logger
  alias Kafee.Consumer.BroadwayAdapter

  @typedoc "All available options for a Kafee.Consumer.BroadwayAdapter module"
  @type options() :: [unquote(NimbleOptions.option_typespec(@options_schema))]

  @doc false
  def child_spec(ini_args) do
    default = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, ini_args},
      type: :supervisor
    }

    Supervisor.child_spec(default, [])
  end

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
        options: options
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
        base_config
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
  def handle_message(:default, %Broadway.Message{metadata: metadata} = message, %{
        consumer: consumer,
        options: options
      }) do
    hydrated_message = %{message | metadata: metadata |> Map.put(:consumer, consumer) |> Map.put(:options, options)}
    {:ok, adapter_options} = validate_adapter_options(options)
    batch_config = adapter_options[:batching]

    if batch_config do
      hydrated_message
    else
      do_consumer_work(hydrated_message)
      message
    end
  end

  @impl Broadway
  def handle_batch(:default, messages, _batch_info, context) do
    {:ok, adapter_options} = validate_adapter_options(context[:options])
    batch_config = adapter_options[:batching]

    if batch_config[:async_run] do
      tasks =
        Enum.map(
          messages,
          &Task.Supervisor.async_nolink({:via, PartitionSupervisor, {BroadwayAdapter.TaskSupervisors, self()}}, fn ->
            do_consumer_work(&1)
          end)
        )

      Task.await_many(tasks)
    else
      Enum.each(messages, &do_consumer_work/1)
    end

    messages
  end

  defp do_consumer_work(%Broadway.Message{
         data: value,
         metadata: %{consumer: consumer, options: options} = metadata
       }) do
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
  end

  @doc false
  @impl Broadway
  def handle_failed(messages, %{consumer: consumer}) do
    # This error only occurs when there is an issue with the `handle_message/2`
    # function above because `Kafee.Consumer.Adapter.push_message/2` will catch any
    # errors.

    error = %RuntimeError{message: "Error converting a Broadway message to Kafee.Consumer.Message"}
    consumer.handle_failure(error, messages)

    messages
  end
end
