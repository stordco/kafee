defmodule Kafee.Consumer.BroadwayBackend do
  @options_schema NimbleOptions.new!(
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
                    ]
                  )

  # credo:disable-for-lines:10 /\.Readability\./
  @moduledoc """
  A Kafee consumer backend based on the exceptional `Broadway` library.
  This backend is made for maximum freight train throughput with no
  stopping. **All messages are acknowledged immediately** after being
  received. This means that you are responsible for creating some logic
  to handle failed messages, **or they will be dropped**.

  ## Options

  #{NimbleOptions.docs(@options_schema)}
  """

  @behaviour Broadway
  @behaviour Kafee.Consumer.Backend

  require Logger

  @typedoc "All available options for a Kafee.Consumer.BroadwayBackend module"
  @type options() :: unquote(NimbleOptions.option_typespec(@options_schema))

  @doc false
  @impl Kafee.Consumer.Backend
  @spec start_link(module(), Kafee.Consumer.options(), Keyword.t()) :: Supervisor.on_start()
  def start_link(module, options, backend_options) do
    with {:ok, backend_options} <- NimbleOptions.validate(backend_options, @options_schema) do
      Broadway.start_link(__MODULE__,
        name: module,
        context: %{
          consumer_group: options[:consumer_group_id],
          module: module
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
          concurrency: backend_options[:consumer_concurrency]
        ],
        processors: [
          default: [
            concurrency: processor_concurrency(backend_options)
          ]
        ]
      )
    end
  end

  defp client_config(options) do
    options
    |> Keyword.take([:sasl, :ssl])
    |> Keyword.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp processor_concurrency(backend_options),
    do: Keyword.get(backend_options, :processor_concurrency, System.schedulers_online() * 2)

  @doc false
  @impl Broadway
  def handle_message(:default, %Broadway.Message{data: value, metadata: metadata} = message, %{
        consumer_group: consumer_group,
        module: module
      }) do
    :ok =
      Kafee.Consumer.push_message(module, %Kafee.Consumer.Message{
        key: metadata.key,
        value: value,
        topic: metadata.topic,
        partition: metadata.partition,
        offset: metadata.offset,
        consumer_group: consumer_group,
        timestamp: DateTime.from_unix!(metadata.ts, :millisecond),
        headers: metadata.headers
      })

    message
  end

  @doc false
  @impl Broadway
  def handle_failed(message, _context) do
    # This error only occurs when there is an issue with the `handle_message/2`
    # function above because `Kafee.Consumer.push_message/2` will catch any
    # errors.
    Logger.error("Error in Broadway message pipe", message: message)
    message
  end
end
