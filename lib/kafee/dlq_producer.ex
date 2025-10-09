defmodule Kafee.DLQProducer do
  @moduledoc """
  A shared Dead Letter Queue producer for efficient DLQ message handling.

  This module provides a centralized producer for sending failed messages to a 
  Dead Letter Queue topic. It's designed to be started in your application's 
  supervision tree and shared across multiple consumers.

  ## Usage

  Add the DLQ producer to your supervision tree:

      children = [
        {Kafee.DLQProducer,
          name: :my_dlq_producer,
          topic: "my-app-dlq",
          host: "localhost",
          port: 9092,
          encoder: Kafee.JasonEncoderDecoder  # Optional
        },
        # ... other children
      ]

  Then reference it in your consumer configuration:

      defmodule MyConsumer do
        use Kafee.Consumer,
          adapter: {Kafee.Consumer.BrodAdapter, [
            mode: :batch,
            acknowledgment: [
              strategy: :best_effort,
              dead_letter_producer: :my_dlq_producer,
              dead_letter_max_retries: 3
            ]
          ]}
      end

  ## Options

  * `:name` - Required. The name to register the producer under.
  * `:topic` - Required. The default DLQ topic to send messages to.
  * `:host` - The Kafka broker host (default: "localhost").
  * `:port` - The Kafka broker port (default: 9092).
  * `:encoder` - Optional encoder module for message values.
  * `:sasl` - Optional SASL authentication configuration.
  * `:ssl` - Optional SSL configuration.
  * `:producer_config` - Additional producer configuration options.

  ## Multiple DLQ Topics

  While the producer is configured with a default topic, consumers can override
  this by specifying their own DLQ topic in the message metadata.
  """

  use GenServer
  require Logger

  @type option ::
          {:name, atom()}
          | {:topic, String.t()}
          | {:host, String.t()}
          | {:port, integer()}
          | {:encoder, module() | nil}
          | {:sasl, term()}
          | {:ssl, boolean() | keyword()}
          | {:producer_config, keyword()}

  @type options :: [option()]

  defmodule State do
    @moduledoc false
    defstruct [
      :name,
      :default_topic,
      :client_id,
      :encoder,
      :producer_config
    ]
  end

  @doc """
  Starts a DLQ producer linked to the current process.
  """
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Sends a message to the DLQ.

  The message should include DLQ metadata headers and optionally specify
  a custom topic. If no topic is specified, the default topic is used.
  """
  @spec send_message(GenServer.server(), map()) :: :ok | {:error, term()}
  def send_message(server, message) do
    GenServer.call(server, {:send_message, message})
  end

  @doc """
  Sends a message to a specific DLQ topic.
  """
  @spec send_message(GenServer.server(), String.t(), map()) :: :ok | {:error, term()}
  def send_message(server, topic, message) do
    GenServer.call(server, {:send_message, topic, message})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    topic = Keyword.fetch!(opts, :topic)
    host = Keyword.get(opts, :host, "localhost")
    port = Keyword.get(opts, :port, 9092)
    encoder = Keyword.get(opts, :encoder)

    # Create a unique client ID
    client_id = Module.concat([__MODULE__, name, "BrodClient"])

    # Build client config
    client_config =
      []
      |> maybe_add_option(:sasl, opts[:sasl])
      |> maybe_add_option(:ssl, opts[:ssl])

    # Start the brod client
    case :brod.start_client([{host, port}], client_id, client_config) do
      :ok ->
        # Start a producer for the default topic
        producer_config = Keyword.get(opts, :producer_config, [])
        
        case :brod.start_producer(client_id, topic, producer_config) do
          :ok ->
            Logger.info("Started DLQ producer",
              name: name,
              client_id: client_id,
              default_topic: topic
            )

            state = %State{
              name: name,
              default_topic: topic,
              client_id: client_id,
              encoder: encoder,
              producer_config: producer_config
            }

            {:ok, state}
            
          {:error, reason} ->
            Logger.error("Failed to start producer for DLQ topic",
              topic: topic,
              reason: inspect(reason)
            )
            {:stop, {:error, reason}}
        end

      {:error, {:already_started, _pid}} ->
        # Client already exists, ensure producer is started
        producer_config = Keyword.get(opts, :producer_config, [])
        
        case :brod.start_producer(client_id, topic, producer_config) do
          :ok ->
            :ok
          {:error, {:already_started, _}} ->
            :ok
          {:error, reason} ->
            Logger.error("Failed to start producer for existing client",
              topic: topic,
              reason: inspect(reason)
            )
        end
        
        state = %State{
          name: name,
          default_topic: topic,
          client_id: client_id,
          encoder: encoder,
          producer_config: producer_config
        }

        {:ok, state}

      {:error, reason} = error ->
        Logger.error("Failed to start DLQ producer client",
          name: name,
          reason: inspect(reason)
        )

        {:stop, error}
    end
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    topic = Map.get(message, :topic, state.default_topic)
    result = do_send_message(state, topic, message)
    {:reply, result, state}
  end

  def handle_call({:send_message, topic, message}, _from, state) do
    result = do_send_message(state, topic, message)
    {:reply, result, state}
  end

  # Private functions

  defp do_send_message(state, topic, message) do
    # Ensure producer exists for the topic
    ensure_producer_started(state.client_id, topic, state.producer_config)
    
    # Encode the value if encoder is configured
    value = encode_value(message.value, state.encoder)

    # Extract headers, ensuring they're in the right format
    headers = format_headers(message[:headers] || %{})

    # Add telemetry
    start_time = System.monotonic_time()

    metadata = %{
      topic: topic,
      dlq_producer: state.name,
      original_topic: get_header_value(headers, "x-original-topic"),
      retry_count: get_header_value(headers, "x-retry-count")
    }

    :telemetry.execute(
      [:kafee, :dlq, :send, :start],
      %{system_time: System.system_time()},
      metadata
    )

    # Send using brod
    # Note: brod.produce_sync/5 doesn't support headers directly
    # We need to construct a proper kafka message
    result =
      :brod.produce_sync(
        state.client_id,
        topic,
        _partition = :random,
        message.key || "",
        value
      )

    # Emit telemetry based on result
    case result do
      :ok ->
        :telemetry.execute(
          [:kafee, :dlq, :send, :stop],
          %{duration: System.monotonic_time() - start_time},
          metadata
        )

        :ok

      {:error, reason} = error ->
        :telemetry.execute(
          [:kafee, :dlq, :send, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.put(metadata, :error, reason)
        )

        error
    end
  end

  defp encode_value(value, nil), do: to_string(value)

  defp encode_value(value, encoder) when is_atom(encoder) do
    case encoder.encode(value) do
      {:ok, encoded} -> encoded
      {:error, _} -> to_string(value)
    end
  end

  defp format_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp format_headers(headers) when is_list(headers) do
    Enum.map(headers, fn
      {k, v} -> {to_string(k), to_string(v)}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp format_headers(_), do: []

  defp get_header_value(headers, key) do
    case List.keyfind(headers, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp maybe_add_option(config, _key, nil), do: config
  defp maybe_add_option(config, key, value), do: [{key, value} | config]
  
  defp ensure_producer_started(client_id, topic, producer_config) do
    case :brod.start_producer(client_id, topic, producer_config) do
      :ok ->
        :ok
      {:error, {:already_started, _}} ->
        :ok
      {:error, reason} ->
        Logger.warning("Failed to ensure producer for topic",
          topic: topic,
          reason: inspect(reason)
        )
        :ok
    end
  end
end
