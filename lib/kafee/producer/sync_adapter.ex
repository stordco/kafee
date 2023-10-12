defmodule Kafee.Producer.SyncAdapter do
  @moduledoc """
  This is an synchronous adapter for sending messages to Kafka.
  This will block the process until acknowledgement from Kafka
  before continuing. See `:brod.produce_sync` for more details.
  """

  @behaviour Kafee.Producer.Adapter

  alias Datadog.DataStreams.Integrations.Kafka, as: DDKafka
  alias Kafee.Producer.Config

  @doc """
  Child specification for the lower level `:brod_client`.
  """
  @impl Kafee.Producer.Adapter
  def child_spec([config]) do
    brod_endpoints = Config.brod_endpoints(config)
    brod_client_opts = Config.brod_client_config(config)

    %{
      id: config.brod_client_id,
      start: {:brod_client, :start_link, [brod_endpoints, config.brod_client_id, brod_client_opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @doc """
  Returns a partition number for the given message under a topic. This uses
  the underlying `:brod` library partitioning logic. The given partition
  function can either be `:random`, `:hash`, or a function. See
  `:brod.partition_fun()` for more details.

  ## Examples

      iex> partition(%Config{}, message)
      {:ok, 1}

  """
  @impl Kafee.Producer.Adapter
  def partition(%Config{brod_client_id: brod_client_id}, message) do
    with {:ok, partition_count} <- :brod.get_partitions_count(brod_client_id, message.topic) do
      partition_fun = :brod_utils.make_part_fun(message.partition_fun)
      partition_fun.(message.topic, partition_count, message.key, message)
    end
  end

  @doc """
  Calls the `:brod.produce_sync/5` function.
  """
  @impl Kafee.Producer.Adapter
  @dialyzer {:no_match, produce: 2}
  def produce(%Config{} = config, messages) do
    for message <- messages do
      :telemetry.span([:kafee, :produce], %{topic: message.topic, partition: message.partition}, fn ->
        # We pattern match here because it will cause `:telemetry.span/3` to measure exceptions
        {:ok, offset} =
          :brod.produce_sync_offset(config.brod_client_id, message.topic, message.partition, message.key, message)

        if is_integer(offset), do: DDKafka.track_produce(message.topic, message.partition, offset)

        {:ok, %{}}
      end)
    end

    :ok
  rescue
    e in MatchError -> e.term
  end
end