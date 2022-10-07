defmodule Kafee.Producer.AsyncSupervisor do
  @moduledoc """
  This is a `DynamicSupervisor` responsible for handling each
  `Kafee.Producer.AsyncWorker` process.
  """

  use DynamicSupervisor

  alias Kafee.Producer.{AsyncRegistry, AsyncWorker}

  @doc false
  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts this `DynamicSupervisor`.

  ## Options

      - `brod_client_id` A unique atom representing this processing tree.
        It is used to partition the `Kafee.Producer.AsyncRegistry`.

  """
  @spec start_link(Keyword.t()) :: Supervisor.on_start()
  def start_link(opts) do
    brod_client_id = Keyword.fetch!(opts, :brod_client_id)

    DynamicSupervisor.start_link(__MODULE__, opts, name: process_name(brod_client_id))
  end

  @doc """
  Creates a new `Kafee.Producer.AsyncWorker` for the given brod client,
  topic, and partition.
  """
  @spec create_worker(:brod.client(), :brod.topic(), :brod.partition(), Keyword.t()) :: {:ok, pid()} | {:error, term()}
  def create_worker(brod_client_id, topic, partition, opts \\ []) do
    full_opts = Keyword.merge(opts, [brod_client_id: brod_client_id, topic: topic, partition: partition])
    DynamicSupervisor.start_child(__MODULE__, {AsyncWorker, full_opts})
  end

  @doc """
  Retrieves the pid of of a currently running `Kafee.Producer.AsyncWorker`
  based on the brod client, topic, and partition.
  """
  @spec get_worker(:brod.client(), :brod.topic(), :brod.partition()) :: {:ok, pid()} | {:error, term()}
  def get_worker(brod_client_id, topic, partition) do
    case Registry.lookup(AsyncRegistry, AsyncWorker.process_name(brod_client_id, topic, partition)) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Retrieves the pid of a currently running `Kafee.Producer.AsyncWorker` or
  creates a new one if it is not currently running.
  """
  @spec get_or_create_worker(:brod.client(), :brod.topic(), :brod.partition(), Keyword.t()) :: {:ok, pid()} | {:error, term()}
  def get_or_create_worker(brod_client_id, topic, partition, opts \\ []) do
    with {:error, :not_found} <- get_worker(brod_client_id, topic, partition) do
      create_worker(brod_client_id, topic, partition, opts)
    end
  end

  @doc """
  Queues messages to a queue given the brod client, topic, and partition.
  """
  @spec queue(:brod.client(), :brod.topic(), :brod.partition(), :brod.message() | :brod.message_set()) :: :ok | {:error, term()}
  def queue(brod_client_id, topic, partition, message_or_messages) do
    with {:ok, pid} <- get_or_create_worker(brod_client_id, topic, partition) do
      AsyncWorker.queue(pid, message_or_messages)
    end
  end

  @doc """
  Creates a process name via the `Kafee.Producer.AsyncRegistry`.

  ## Examples

      iex> process_name(:test)
      {:via, Registry, {Kafee.Producer.AsyncRegistry, _}}

  """
  @spec process_name(:brod.client()) :: Supervisor.name()
  def process_name(brod_client_id) do
    {:via, Registry, {AsyncRegistry, {brod_client_id, :supervisor}}}
  end
end
