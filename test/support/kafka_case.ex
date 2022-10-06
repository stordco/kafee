defmodule Kafee.KafkaCase do
  @moduledoc """
  A ExUnit case that helps with interacting with a live Kafka instance.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Kafee.KafkaCase
    end
  end

  setup context do
    if topic = context[:topic] do
      partitions = Keyword.get(context, :partitions, 1)

      :ok = create_kafka_topic(topic, partitions)

      on_exit(fn ->
        delete_kafka_topic(topic)
      end)
    end

    # I know this is bad. I know why. Blame `:brod` for requiring an atom
    # key for clients and their whole library supervisor tree thing.
    random_string = for _ <- 1..10, into: "", do: <<Enum.at('0123456789abcdef', :rand.uniform(15))>>
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    brod_client_id = String.to_atom(random_string)
    brod_client!(brod_client_id)

    {:ok, %{brod_client_id: brod_client_id}}
  end

  @doc """
  Creates new Kafka topic.
  """
  @spec create_kafka_topic(binary(), non_neg_integer()) :: :ok
  def create_kafka_topic(name, partitions \\ 1) do
    configs = [
      %{
        num_partitions: partitions,
        name: name
      }
    ]

    :brod.create_topics(brod_endpoints(), configs, %{timeout: 100_000})
  end

  @doc """
  Deletes a Kafka topic.
  """
  @spec delete_kafka_topic(binary()) :: :ok
  def delete_kafka_topic(name) do
    :brod.delete_topics(brod_endpoints(), [name], 100_000)
  end

  @doc """
  Returns the Kafka instance host.
  """
  @spec kafka_host() :: binary()
  def kafka_host do
    System.get_env("KAFKA_HOST", "localhost")
  end

  @doc """
  Returns the kafka instance port.
  """
  @spec kafka_port() :: non_neg_integer()
  def kafka_port do
    "KAFKA_PORT"
    |> System.get_env("9092")
    |> String.to_integer()
  end

  @doc """
  Starts a new `:brod_client`.
  """
  @spec brod_client!(atom()) :: pid()
  def brod_client!(brod_client_id) do
    start_supervised!(%{
      id: brod_client_id,
      start: {:brod_client, :start_link, [brod_endpoints(), brod_client_id, brod_client_config()]}
    })
  end

  @doc """
  Returns endpoints you can put directly into `:brod`.
  """
  @spec brod_endpoints() :: list({binary(), non_neg_integer()})
  def brod_endpoints do
    [{kafka_host(), kafka_port()}]
  end

  @doc """
  Returns a list of client options to put into `:brod_client`.
  """
  @spec brod_client_config() :: Keyword.t()
  def brod_client_config do
    [query_api_version: false]
  end
end
