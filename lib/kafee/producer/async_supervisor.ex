defmodule Kafee.Producer.AsyncSupervisor do
  @moduledoc """
  This is a `DynamicSupervisor` responsible for handling each
  `Kafee.Producer.AsyncWorker` process.
  """

  use DynamicSupervisor

  alias Kafee.Producer.{AsyncRegistry, AsyncWorker, Config}

  @doc false
  @impl true
  def init(_config) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts this `DynamicSupervisor`.
  """
  @spec start_link(Config.t()) :: Supervisor.on_start()
  def start_link(%Config{} = config) do
    DynamicSupervisor.start_link(__MODULE__, config, name: process_name(config))
  end

  @doc """
  Creates a new `Kafee.Producer.AsyncWorker` for the given brod client,
  topic, and partition.
  """
  @spec create_worker(Config.t(), :brod.topic(), :brod.partition()) :: {:ok, pid()} | {:error, term()}
  def create_worker(%Config{} = config, topic, partition) do
    full_opts =
      Keyword.merge(config.kafee_async_worker_opts,
        brod_client_id: config.brod_client_id,
        topic: topic,
        partition: partition
      )

    with {:error, {:already_started, pid}} <-
           DynamicSupervisor.start_child(process_name(config), {AsyncWorker, full_opts}) do
      {:ok, pid}
    end
  end

  @doc """
  Retrieves the pid of of a currently running `Kafee.Producer.AsyncWorker`
  based on the brod client, topic, and partition.
  """
  @spec get_worker(Config.t(), :brod.topic(), :brod.partition()) :: {:ok, pid()} | {:error, term()}
  def get_worker(%Config{} = config, topic, partition) do
    case Registry.lookup(AsyncRegistry, AsyncWorker.process_name(config.brod_client_id, topic, partition)) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Retrieves the pid of a currently running `Kafee.Producer.AsyncWorker` or
  creates a new one if it is not currently running.
  """
  @spec get_or_create_worker(Config.t(), :brod.topic(), :brod.partition()) :: {:ok, pid()} | {:error, term()}
  def get_or_create_worker(%Config{} = config, topic, partition) do
    with {:error, :not_found} <- get_worker(config, topic, partition) do
      create_worker(config, topic, partition)
    end
  end

  @doc """
  Queues messages to a queue given the brod client, topic, and partition.
  """
  @spec queue(Config.t(), :brod.topic(), :brod.partition(), :brod.message_set()) ::
          :ok | {:error, term()}
  def queue(%Config{} = config, topic, partition, messages) do
    with {:ok, pid} <- get_or_create_worker(config, topic, partition) do
      AsyncWorker.queue(pid, messages)
    end
  end

  @doc """
  Creates a process name via the `Kafee.Producer.AsyncRegistry`.

  ## Examples

      iex> process_name(%Config{producer: MyProducer})
      {:via, Registry, {Kafee.Producer.AsyncRegistry, _}}

  """
  @spec process_name(Config.t()) :: Supervisor.name()
  def process_name(%Config{producer: producer}) do
    {:via, Registry, {AsyncRegistry, {producer, :supervisor}}}
  end
end
