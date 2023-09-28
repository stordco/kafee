defmodule Kafee.KafkaApi do
  @moduledoc """
  Some useful functions for interacting with a live Kafka instance.
  """

  @doc """
  Generates a random topic string. Does not actually create it.
  """
  @spec generate_topic :: binary()
  def generate_topic do
    4 |> Faker.Lorem.words() |> Enum.join("-")
  end

  @doc """
  Creates new Kafka topic.
  """
  @spec create_topic(binary(), non_neg_integer()) :: :ok
  def create_topic(topic, partitions \\ 1) do
    configs = [
      %{
        assignments: [],
        configs: [],
        name: topic,
        num_partitions: partitions,
        replication_factor: 1
      }
    ]

    :brod.create_topics(endpoints(), configs, %{timeout: 100_000})
  end

  @doc """
  Deletes a Kafka topic.
  """
  @spec delete_topic(binary()) :: :ok
  def delete_topic(topic) do
    :brod.delete_topics(endpoints(), [topic], 100_000)
  end

  @doc """
  Returns the Kafka instance host.
  """
  @spec host() :: binary()
  def host do
    System.get_env("KAFKA_HOST", "127.0.0.1")
  end

  @doc """
  Returns the kafka instance port.
  """
  @spec port() :: non_neg_integer()
  def port do
    "KAFKA_PORT"
    |> System.get_env("9092")
    |> String.to_integer()
  end

  @doc """
  Returns endpoints you can put directly into `:brod`.
  """
  @spec endpoints() :: list({binary(), non_neg_integer()})
  def endpoints do
    [{host(), port()}]
  end
end
