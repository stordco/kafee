defmodule Kafee.Producer.SyncBackend do
  @moduledoc """
  This is an synchronous backend for sending messages to Kafka.
  This will block the process until acknowledgement from Kafka
  before continuing. See `:brod.produce_sync` for more details.
  """

  @behaviour Kafee.Producer.Backend

  use Supervisor

  alias Kafee.Producer.Config

  @doc false
  @impl true
  def init(%Config{} = config) do
    brod_endpoints = Config.brod_endpoints(config)
    brod_client_opts = Config.brod_client_config(config)

    children = [
      %{
        id: config.brod_client_id,
        start: {:brod_client, :start_link, [brod_endpoints, config.brod_client_id, brod_client_opts]}
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def init(opts) do
    raise ArgumentError,
      message: """
      The `Kafee.Producer.SyncBackend` module expects to be given
      a `Kafee.Producer.Config` struct on startup.

      Received:
      #{inspect(opts)}
      """
  end

  @doc """
  Starts a new `Kafee.Producer.SyncBackend` process and associated children.
  """
  @impl true
  def start_link(%Config{} = config) do
    Supervisor.start_link(__MODULE__, config, name: Kafee.Producer.Backend.process_name(config.producer))
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
  @impl true
  def partition(%Config{brod_client_id: brod_client_id}, message) do
    with {:ok, partition_count} <- :brod.get_partitions_count(brod_client_id, message.topic) do
      partition_fun = :brod_utils.make_part_fun(message.partition_fun)
      partition_fun.(message.topic, partition_count, message.key, message)
    end
  end

  @doc """
  Calls the `:brod.produce_sync/5` function.
  """
  @impl true
  def produce(%Config{} = config, messages) do
    for message <- messages do
      :brod.produce_sync(config.brod_client_id, message.topic, message.partition, message.key, message.value)
    end

    :ok
  end
end
