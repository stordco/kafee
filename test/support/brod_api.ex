defmodule Kafee.BrodApi do
  @moduledoc """
  Some useful functions for interacting with `:brod`.
  """

  import ExUnit.Callbacks, only: [start_supervised!: 1]

  @data_streams_propagator_key Datadog.DataStreams.Propagator.propagation_key()

  @doc """
  Creates a random atom to use as a `:brod_client` id.

  Note: this function uses `String.to_atom/1` and is unsafe for production
  workloads.
  """
  @spec generate_client_id :: atom()
  def generate_client_id do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    String.to_atom(Faker.Beer.name())
  end

  @doc """
  Starts a new `:brod_client`.
  """
  @spec client!(atom()) :: pid()
  def client!(brod_client_id) do
    start_supervised!(%{
      id: brod_client_id,
      start: {:brod_client, :start_link, [endpoints(), brod_client_id, client_config()]}
    })
  end

  @doc """
  Returns a list of client options to put into `:brod_client`.
  """
  @spec client_config() :: Keyword.t()
  def client_config do
    [
      auto_start_producers: true,
      query_api_version: false
    ]
  end

  @doc """
  Generates a list of `Kafee.Consumer.Message` for testing.
  """
  def generate_consumer_message_list(number, options \\ []) do
    Enum.map(1..number, fn _ -> generate_consumer_message(options) end)
  end

  @doc """
  Generates a `Kafee.Consumer.Message` for testing.
  """
  def generate_consumer_message(options \\ []) do
    struct!(
      Kafee.Consumer.Message,
      Keyword.merge(
        [
          key: "test",
          value: "test",
          topic: "test",
          partition: 0,
          offset: 0,
          consumer_group: "test",
          timestamp: DateTime.utc_now(),
          headers: []
        ],
        options
      )
    )
  end

  @doc """
  Generates a list of `Kafee.Producer.Message` for testing.
  """
  def generate_producer_message_list(context_or_topic, number \\ 1),
    do: Enum.map(1..number, fn _ -> generate_producer_message(context_or_topic) end)

  @doc """
  Generates a `Kafee.Producer.Message` for testing.
  """
  def generate_producer_message(%{topic: topic}),
    do: generate_producer_message(topic)

  def generate_producer_message(topic) do
    %Kafee.Producer.Message{
      key: "test",
      value: "test",
      topic: topic,
      partition: 0,
      partition_fun: :random,
      headers: [{@data_streams_propagator_key, "test"}]
    }
  end

  @doc """
  Generates a list of messages that tries to spread evenly across the given number of partitions.
  Returns error if number of partitions is greater than number of messages to create.
  """
  def generate_producer_partitioned_message_list(topic, number_of_messages, partitions \\ 1)

  def generate_producer_partitioned_message_list(topic, number_of_messages, partitions)
      when length(number_of_messages) < length(partitions) do
    {:error, "number of partitions is greather than number of messages"}
  end

  def generate_producer_partitioned_message_list(topic, number_of_messages, partitions) do
    messages = generate_producer_message_list(topic, number_of_messages)
    chunk_every = Kernel.floor(number_of_messages / partitions)

    messages
    |> Enum.chunk_every(chunk_every)
    |> Enum.with_index()
    |> Enum.flat_map(fn {chunked_messages, idx} ->
      Enum.map(chunked_messages, fn message ->
        %{message | partition: idx}
      end)
    end)

    # # change partitions
    # messages = messages |> Enum.with_index(1) |> Enum.map(fn {message, idx} -> %{message | partition: idx} end)
  end

  @doc """
  Returns a simple map of all of the message fields we send to brod and Kafka.
  """
  @spec to_kafka_message(value) :: value when value: Message.t() | [Message.t()]
  def to_kafka_message(messages) when is_list(messages),
    do: Enum.map(messages, &to_kafka_message/1)

  def to_kafka_message(%Kafee.Producer.Message{} = message),
    do: Map.take(message, [:key, :value, :headers])

  defdelegate host(), to: Kafee.KafkaApi
  defdelegate port(), to: Kafee.KafkaApi
  defdelegate endpoints(), to: Kafee.KafkaApi
end
