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

  @typedoc "All available options for a Kafee.Consumer.BroadwayAdapter module"
  @type options() :: [unquote(NimbleOptions.option_typespec(@options_schema))]

  @doc false
  @impl Kafee.Consumer.Adapter
  @spec start_link(module(), Kafee.Consumer.options()) :: Supervisor.on_start()
  def start_link(consumer, options) do
    adapter_options =
      case options[:adapter] do
        nil -> []
        adapter when is_atom(adapter) -> []
        {_adapter, adapter_options} -> adapter_options
      end

    with {:ok, adapter_options} <- NimbleOptions.validate(adapter_options, @options_schema) do
      Broadway.start_link(__MODULE__,
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
  def handle_message(:default, %Broadway.Message{data: value, metadata: metadata} = message, %{
        consumer: consumer,
        options: options
      }) do
    Kafee.Consumer.Adapter.push_message(consumer, options, %Kafee.Consumer.Message{
      key: metadata.key,
      value: value,
      topic: metadata.topic,
      partition: metadata.partition,
      offset: metadata.offset,
      consumer_group: options[:consumer_group_id],
      timestamp: DateTime.from_unix!(metadata.ts, :millisecond),
      headers: metadata.headers
    })

    message
  end

  @doc false
  @impl Broadway
  def handle_failed(message, %{consumer: consumer}) do
    # This error only occurs when there is an issue with the `handle_message/2`
    # function above because `Kafee.Consumer.Adapter.push_message/2` will catch any
    # errors.

    error = %RuntimeError{message: "Error converting a Broadway message to Kafee.Consumer.Message"}
    consumer.handle_failure(error, message)

    message
  end
end
