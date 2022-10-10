defmodule Kafee.Producer.AsyncWorker do
  @moduledoc """
  A simple GenServer for every topic * partition in Kafka. It holds an
  erlang `:queue` and sends messages every so often. On process close, we
  attempt to send all messages to Kafka, and in the unlikely event we can't
  we write all messages to the logs.
  """

  use GenServer,
    shutdown: :timer.seconds(10)

  require Logger

  defstruct [
    :brod_client_id,
    :partition,
    :send_count,
    :send_count_max,
    :send_interval_ref,
    :send_ref,
    :topic,
    :queue
  ]

  @type t :: %__MODULE__{
          brod_client_id: :brod.client_id(),
          partition: :brod.partition(),
          send_count: non_neg_integer(),
          send_interval_ref: reference(),
          send_ref: :brod.call_ref() | nil,
          topic: :brod.topic(),
          queue: :queue.queue()
        }

  @type opts :: [
          brod_client_id: :brod.client(),
          topic: :brod.topic(),
          partition: :brod.partition(),
          send_count_max: pos_integer(),
          send_interval: pos_integer() | nil
        ]

  @doc false
  @spec init(opts()) :: {:ok, t()}
  def init(opts) do
    Process.flag(:trap_exit, true)

    brod_client_id = Keyword.fetch!(opts, :brod_client_id)
    topic = Keyword.fetch!(opts, :topic)
    partition = Keyword.fetch!(opts, :partition)
    send_count_max = Keyword.get(opts, :send_count_max, 100)
    send_interval = Keyword.get(opts, :send_interval, :timer.seconds(10))

    send_interval_ref = Process.send_after(self(), :send, send_interval)

    {:ok,
     %__MODULE__{
       brod_client_id: brod_client_id,
       partition: partition,
       send_count: 0,
       send_count_max: send_count_max,
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
    send_interval_ref = Process.send_after(self(), :send, state.send_interval)
    {:noreply, %{state | send_interval_ref: send_interval_ref}}
  end

  # If the `send_ref` state is nil, that means we don't currently have a
  # Kafka request in progress, so we are safe to send more messages.
  @doc false
  def handle_info(:send, %{send_ref: nil} = state) do
    {send_messages, _remaining_messages} = :queue.split(state.send_count_max, state.queue)
    messages = :queue.to_list(send_messages)
    messages_count = length(messages)

    {:ok, send_ref} = :brod.produce(state.brod_client_id, state.topic, state.partition, :undefined, messages)
    send_interval_ref = Process.send_after(self(), :send, state.send_interval)

    {:noreply, %{state | send_count: messages_count, send_interval_ref: send_interval_ref, send_ref: send_ref}}
  rescue
    err in MatchError ->
      Logger.warn(
        """
          Unable to send message to Kafka because the `:brod_producer` is not found.
          This usually indicates that you are using the `Kafee.Producer.AsyncWorker`
          directly without setting `auto_state_producers` to `true` in when creating
          your `:brod_client` instance.

          #{inspect(err)}
        """,
        topic: state.topic,
        partition: state.partition
      )

      {:noreply, state}

    err ->
      Logger.error(
        """
          Kafee received an unknown error when trying to send messages to Kafka.

          #{inspect(err)}
        """,
        topic: state.topic,
        partition: state.partition
      )

      {:noreply, state}
  after
    send_interval_ref = Process.send_after(self(), :send, state.send_interval)
    {:noreply, %{state | send_interval_ref: send_interval_ref}}
  end

  # If we get here, we already have something in flight to Kafka, so we
  # do nothing and just keep on waiting.
  @doc false
  def handle_info(:send, state) do
    send_interval_ref = Process.send_after(self(), :send, state.send_interval)
    {:noreply, %{state | send_interval_ref: send_interval_ref}}
  end

  # This is the message we get from `:brod` after Kafka has acknowledged
  # messages have been received. When this happens, we can safely remove
  # those messages from the queue and send more messages. Because this is
  # from erlang, the pattern matching is a little weird.
  @doc false
  def handle_info(
        {:brod_produce_reply, send_ref, _offset, :brod_produce_req_acked},
        %{send_ref: send_ref} = state
      ) do
    {_sent_messages, remaining_messages} = :queue.split(state.send_count, state.queue)
    send_interval_ref = Process.send_after(self(), :send, state.send_interval)
    {:noreply, %{state | queue: remaining_messages, send_count: 0, send_interval_ref: send_interval_ref, send_ref: nil}}
  end

  # This handles the very rare (and dangerous) case where we get an
  # acknowledgement from Kafka, that doesn't match the last group of messages
  # we sent. This _shouldn't_ happen, but if it does, it means state
  # inconsistency in the form of duplicated messages in Kafka or missing
  # messages in Kafka.
  @doc false
  def handle_info({:brod_produce_reply, _send_ref, _offset, :brod_produce_req_acked}, state) do
    Logger.warn("Brod acknowledgement received that doesn't match internal records",
      topic: state.topic,
      partition: state.partition
    )

    send_interval_ref = Process.send_after(self(), :send, state.send_interval)
    {:noreply, %{state | send_interval_ref: send_interval_ref}}
  end

  # This handles the case if Brod sends a non successful acknowledgement.
  @doc false
  def handle_info({:brod_produce_reply, _send_ref, _offset, resp}, state) do
    Logger.warn(
      """
      Brod acknowledgement received, but it wasn't successful.

      Response:
      #{inspect(resp)}
      """,
      topic: state.topic,
      partition: state.partition
    )

    send_interval_ref = Process.send_after(self(), :send, state.send_interval)
    {:noreply, %{state | send_interval_ref: send_interval_ref}}
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
    :ok = :brod.produce_sync(state.brod_client_id, state.topic, state.partition, :undefined, messages)
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

      iex> init([brod_client_id: :brod_client_id, topic: "test-topic", partition: 1])
      {:ok, _pid}

  ## Options

  This GenServer requires the following fields to be given on creation.

    - `brod_client_id` The id given when you created a `:brod_client`.
    - `topic` The Kafka topic to publish to.
    - `partition` The Kafka partition of the topic to publish to.

  This function also takes additional optional fields.

    - `send_interval` (10_000) The amount of time we should wait before
      attempting to send messages to Kafka.

  """
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts) do
    brod_client_id = Keyword.fetch!(opts, :brod_client_id)
    topic = Keyword.fetch!(opts, :topic)
    partition = Keyword.fetch!(opts, :partition)

    GenServer.start_link(__MODULE__, opts, name: process_name(brod_client_id, topic, partition))
  end

  @doc """
  Adds messages to the send queue.

  ## Examples

      iex> queue(async_worker_pid, [message_one, message_two])
      :ok

  """
  @spec queue(pid(), :brod.message_set()) :: :ok
  def queue(pid, messages) do
    GenServer.cast(pid, {:queue, messages})
  end

  @doc """
  Creates a process name via `Kafee.Producer.AsyncRegistry`.

  ## Examples

      iex> process_name(:test, :topic, 1)
      {:via, Registry, {Kafee.Producer.AsyncRegistry, _}}

  """
  @spec process_name(:brod.client(), :brod.topic(), :brod.partition()) :: GenServer.name()
  def process_name(brod_client_id, topic, partition) do
    {:via, Registry, {Kafee.Producer.AsyncRegistry, {brod_client_id, :worker, topic, partition}}}
  end
end
