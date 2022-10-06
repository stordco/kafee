defmodule Kafee.Producer.AsyncWorker do
  @moduledoc """
  A simple GenServer for every topic * partition in Kafka. It holds an
  erlang `:queue` and sends messages every so often. On process close, we
  attempt to send all messages to Kafka, and in the unlikely event we can't
  we write all messages to the logs.
  """

  use GenServer

  require Logger

  defstruct [
    :brod_client_name,
    :partition,
    :send_count,
    :send_interval_ref,
    :send_ref,
    :topic,
    :queue
  ]

  @type t :: %__MODULE__{
          brod_client_name: :brod.client(),
          partition: :brod.partition(),
          send_count: non_neg_integer(),
          send_interval_ref: :timer.tref(),
          send_ref: :brod.call_ref() | nil,
          topic: :brod.topic(),
          queue: :queue.queue()
        }

  @doc false
  @spec init({:brod.client(), :brod.topic(), :brod.partition(), Keyword.t()}) :: {:ok, t()}
  def init({brod_client_name, topic, partition, opts}) do
    Process.flag(:trap_exit, true)

    send_interval = Keyword.get(opts, :send_interval, :timer.seconds(10))
    {:ok, send_interval_ref} = :timer.send_interval(send_interval, :send)

    {:ok,
     %__MODULE__{
       brod_client_name: brod_client_name,
       partition: partition,
       send_count: 0,
       send_interval_ref: send_interval_ref,
       send_ref: nil,
       topic: topic,
       queue: :queue.new()
     }}
  end

  # We ignore any send message if the queue is empty. Save us some time and
  # processing work.
  @doc false
  def handle_info(:send, %{queue: {[], []}} = state) do
    {:noreply, state}
  end

  # If the `send_ref` state is nil, that means we don't currently have a
  # Kafka request in progress, so we are safe to send more messages.
  @doc false
  def handle_info(:send, %{send_ref: nil} = state) do
    messages_count = :queue.len(state.queue)
    messages = :queue.to_list(state.queue)

    {:ok, send_ref} = :brod.produce(state.brod_client_name, state.topic, state.partition, :undefined, messages)

    {:noreply, %{state | send_count: messages_count, send_ref: send_ref}}
  rescue
    err ->
      Logger.error("Unable to send messages to Kafka: #{inspect(err)}", topic: state.topic, partition: state.partition)
      {:noreply, state}
  end

  # If we get here, we already have something in flight to Kafka, so we
  # do nothing and just keep on waiting.
  @doc false
  def handle_info(:send, state) do
    {:noreply, state}
  end

  # This is the message we get from `:brod` after Kafka has acknowledged
  # messages have been received. When this happens, we can safely remove
  # those messages from the queue and send more messages. Because this is
  # from erlang, the pattern matching is a little weird.
  @doc false
  def handle_info(
        %{
          __struct__: :brod_produce_reply,
          call_ref: send_ref
        },
        %{send_ref: send_ref} = state
      ) do
    {_sent_messages, remaining_messages} = :queue.split(state.send_count, state.queue)
    {:noreply, %{state | queue: remaining_messages, send_count: 0, send_ref: nil}}
  end

  # This handles the very rare (and dangerous) case where we get an
  # acknowledgement from Kafka, that doesn't match the last group of messages
  # we sent. This _shouldn't_ happen, but if it does, it means state
  # inconsistency in the form of duplicated messages in Kafka or missing
  # messages in Kafka.
  @doc false
  def handle_info(%{__struct__: :brod_produce_reply}, state) do
    Logger.warn("Brod acknowledgement received that doesn't match internal records",
      topic: state.topic,
      partition: state.partition
    )

    {:noreply, state}
  end

  # A simple request to add more messages to the queue. Nothing fancy here.
  @doc false
  def handle_cast({:queue, messages}, state) do
    new_queue = :queue.join(state.queue, :queue.from_list(messages))
    {:noreply, %{state | queue: new_queue}}
  end

  # This callback is called when the GenServer is being closed. In this case
  # the queue is already empty so we have nothing to do.
  @doc false
  def terminate(_reason, %{queue: {[], []}}) do
    Logger.debug("Stopping Kafee async worker with empty queue")
  end

  # In this case, we still have messages to send. We attempt to send them
  # synchronously, and if we fail at that we output them to the logs for
  # developers to handle.
  @doc false
  def terminate(_reason, state) do
    messages = :queue.to_list(state.queue)
    :ok = :brod.produce_sync(state.brod_client_name, state.topic, state.partition, :undefined, messages)
  rescue
    err ->
      Logger.error("Unable to send messages to Kafka: #{inspect(err)}", topic: state.topic, partition: state.partition)

      for message <- :queue.to_list(state.queue) do
        Logger.error("Unsent Kafka message", message: message, topic: state.topic, partition: state.partition)
      end
  end

  ## Client API

  @doc """
  Starts the GenServer with information about our Kafka instance.

  ## Examples

      iex> init(:brod_client_name, "test-topic", 0)
      {:ok, _pid}

      iex> init(:brod_client_name, "test-topic", 1, opts)
      {:ok, _pid}

  ## Options

  This function takes an optional 4th argument for additional options listed
  below.

    - `send_interval` (10_000) The amount of time we should wait before
      attempting to send messages to Kafka.

  """
  @spec start_link(:brod.client(), :brod.topic(), :brod.partition(), Keyword.t()) :: GenServer.on_start()
  def start_link(brod_client_name, topic, partition, opts \\ []) do
    GenServer.start_link(__MODULE__, {brod_client_name, topic, partition, opts})
  end

  @doc """
  Adds a message to the send queue.

  ## Examples

      iex> queue(async_worker_pid, message)
      :ok

      iex> queue(async_worker_pid, [message_one, message_two])
      :ok

  """
  @spec queue(pid(), map() | [map()]) :: :ok
  def queue(pid, messages) when is_list(messages) do
    GenServer.cast(pid, {:queue, messages})
  end

  def queue(pid, message) do
    GenServer.cast(pid, {:queue, [message]})
  end
end
