defmodule Kafee.Producer.TestBackend do
  @moduledoc """
  This is a backend that stores all sent messages in it's local
  process state. This is most useful when running tests and
  you want to ensure a message was sent to Kafka. See the
  `Kafee.Testing` module for more details on testing
  Kafee.
  """

  @behaviour Kafee.Producer.Backend

  use GenServer

  alias Kafee.Producer.{Backend, Config}

  @doc false
  @impl true
  def init(_config) do
    {:ok, []}
  end

  @doc false
  @impl true
  def handle_cast({:add, new_messages}, saved_messages) do
    {:noreply, new_messages ++ saved_messages}
  end

  @doc false
  @impl true
  def handle_call(:get, _from, saved_messages) do
    {:reply, saved_messages, saved_messages}
  end

  @doc """
  Starts a new `Kafee.Producer.TestBackend` process.
  """
  @impl true
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: Backend.process_name(config.producer))
  end

  @doc """
  This will always return 0 as the partition.
  """
  @impl true
  def partition(_config, message) do
    partition_fun = :brod_utils.make_part_fun(message.partition_fun)
    partition_fun.(message.topic, 1, message.key, message.value)
  end

  @doc """
  Adds messages to the internal memory.
  """
  @impl true
  def produce(%Config{} = config, messages) do
    GenServer.cast(Backend.process_name(config.producer), {:add, messages})
  end
end
