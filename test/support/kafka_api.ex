defmodule Kafee.KafkaApi do
  @moduledoc """
  Some useful functions for interacting with a live Kafka instance.
  """

  @doc """
  Generates a random topic string. Does not actually create it.
  """
  @spec generate_topic :: binary()
  def generate_topic do
    4
    |> Faker.Lorem.words()
    |> Enum.join("-")
    |> String.normalize(:nfd)
    |> String.downcase()
    |> String.replace(~r/[^a-z-\s]/u, "")
    |> String.replace(~r/\s/, "-")
    |> String.slice(0..32)
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

    case :brod.create_topics(endpoints(), configs, %{timeout: 100_000}) do
      {:error, :topic_already_exists} ->
        :ok

      :ok ->
        # We get an odd case were we get an :ok from Kafka but the topic
        # hasn't actually been created, which causes a brod error sending
        # a message. I assume this is from Kafka syncing data in some
        # configurations. Because this is a test and we don't care about
        # performance, we just repeat until we confirm the topic alread exists.
        Process.sleep(100)
        create_topic(topic, partitions)

      result ->
        result
    end
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
    System.get_env("KAFKA_HOST", "localhost")
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
