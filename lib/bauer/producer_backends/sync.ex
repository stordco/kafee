defmodule Bauer.SyncProducerBackend do
  @moduledoc """
  A producer backend that sends Kafka messages synchronously. This has no
  backoff or retry logic and is more useful for testing than in production.

  ## Setup

  First, you will need to set your producer's backend to this module. This
  can be done by specifying the `producer_backend` option. Unless you are
  running your Kafka server on localhost with no authentication, you will
  also want to specify those options as well.

      defmodule MyApp.MyProducer do
        use Bauer.Producer,
          producer_backend: Bauer.SyncProducerBackend,
          host: "localhost",
          port: 9093,
          username: "kafka",
          password: "kafka"
      end

  Here is a list of all the possible options you can provide.

      - `topic` The Kafka topic to setup the producer on. This will start
      a connection pool via brod.

      - `host` The Kafka host. Defaults to `localhost`.
      - `port` The Kafka port. Defaults to `9093`.

      - `ssl` If `:brod` should use ssl when connecting to Kafka. Defaults to `false`.
      - `username` The sasl plain text username.
      - `password` The sasl plain text password.

      - `client_config` Any additional brod configuration to pass when
      running `:brod.start_client/3`. Defaults to `[]`.
      - `producer_config` Any additional brod configuration to pass when
      running `:brod.start_producer/3`. Defaults to `[]`.
  """

  use GenServer

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  def init(opts) do
    brod_client = Keyword.fetch!(opts, :brod_client)
    topic = Keyword.fetch!(opts, :topic)

    host = Keyword.get(opts, :host, "localhost")
    port = Keyword.get(opts, :port, 9092)

    ssl = Keyword.get(opts, :ssl, false)
    username = Keyword.get(opts, :username)
    password = Keyword.get(opts, :password)

    ssl_config = brod_ssl_config(ssl, username, password)
    client_config = Keyword.get(opts, :client_config, [])
    producer_config = Keyword.get(opts, :producer_config, [])

    :ok = :brod.start_client([{host, port}], brod_client, ssl_config ++ client_config)
    :ok = :brod.start_producer(brod_client, topic, producer_config)

    send(self(), :get_partitions)

    {:ok, %{brod_client: brod_client, topic: topic, partitions: 0}}
  end

  defp brod_ssl_config(true, username, password),
    do: [ssl: true, sasl: {:plain, username, password}]

  defp brod_ssl_config(false, _username, _password), do: []

  @doc false
  def handle_info(:get_partitions, state) do
    Process.send_after(self(), :get_partitions, 10_000)

    case :brod_client.get_partitions_count(state.brod_client, state.topic) do
      {:ok, partitions} ->
        {:noreply, %{state | partitions: partitions}}

      _ ->
        {:noreply, state}
    end
  end

  @doc false
  def handle_call({:produce_messages, topic, messages}, _from, state) do
    for message <- messages do
      partition = message.partitioner.partition(state.partitions, message.partition_key)

      {:ok, call_ref} = :brod.produce(state.brod_client, topic, partition, message.key, message.value)

      :ok = :brod.sync_produce_request(call_ref, :infinity)
    end

    {:reply, :ok, state}
  end
end
