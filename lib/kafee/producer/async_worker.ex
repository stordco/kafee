defmodule Kafee.Producer.AsyncWorker do
  @moduledoc """
  A simple GenServer for every topic * partition in Kafka. It holds an
  erlang `:queue` and sends messages every so often. On process close, we
  attempt to send all messages to Kafka, and in the unlikely event we can't
  we write all messages to the logs.

  ## Telemetry Events

  - `kafee.queue.count` - The amount of messages in queue
    waiting to be sent to Kafka. This includes the number of messages currently
    in flight awaiting to be acknowledged from Kafka.

    We recommend capturing this with `last_value/2` like so:

      last_value(
        "kafee.queue.count",
        description: "The amount of messages in queue waiting to be sent to Kafka",
        tags: [:topic, :partition]
      )

  """

  use GenServer,
    shutdown: :timer.seconds(25)

  require Logger

  # The max request size Kafka can handle by default is 1mb.
  # We shrink it by 8kb as an extra precaution for data.
  @max_request_size 992_000

  defstruct [
    :brod_client_id,
    :partition,
    :queue,
    :send_throttle_time,
    :send_ref,
    :send_timeout,
    :topic
  ]

  @typedoc """
  Internal data for the worker. Fields are as follow:

  - `brod_client_id` - The client id used for talking to `:brod`
  - `partition` - The Kafka partition we are sending messages to
  - `queue` - A `:queue` of messages waiting to be sent
  - `send_throttle_time` - A throttle time for sending messages to Kafka
  - `send_ref` - A reference to the task sending messages to Kafka
  - `send_timeout` - The time we should wait for messages to be acked by Kafka
    before assuming the worst and retrying
  - `topic` - The Kafka topic we are sending messages to

  """
  @type t :: %__MODULE__{
          brod_client_id: :brod.client_id(),
          partition: :brod.partition(),
          queue: :queue.queue(),
          send_throttle_time: pos_integer(),
          send_ref: reference() | nil,
          send_timeout: pos_integer(),
          topic: :brod.topic()
        }

  @type opts :: [
          brod_client_id: :brod.client(),
          topic: :brod.topic(),
          partition: :brod.partition(),
          send_throttle_time: pos_integer() | nil,
          send_timeout: pos_integer() | nil
        ]

  @doc false
  @spec init(opts()) :: {:ok, t()}
  def init(opts) do
    Process.flag(:trap_exit, true)

    brod_client_id = Keyword.fetch!(opts, :brod_client_id)
    topic = Keyword.fetch!(opts, :topic)
    partition = Keyword.fetch!(opts, :partition)
    send_throttle_time = Keyword.get(opts, :send_throttle_time, 100)
    send_timeout = Keyword.get(opts, :send_timeout, :timer.seconds(10))

    Logger.metadata(topic: topic, partition: partition)

    {:ok,
     %__MODULE__{
       brod_client_id: brod_client_id,
       partition: partition,
       queue: :queue.new(),
       send_throttle_time: send_throttle_time,
       send_ref: nil,
       send_timeout: send_timeout,
       topic: topic
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
    send_ref = Task.async(fn -> send_messages(state) end)
    {:noreply, %{state | send_ref: send_ref}}
  end

  # If we get here, we already have something in flight to Kafka, so we
  # do nothing and just keep on waiting.
  @doc false
  def handle_info(:send, state) do
    {:noreply, state}
  end

  # We sent messages to Kafka successfully, so we pull them from the message queue
  # and try sending more messages
  @doc false
  def handle_info({task_ref, {:ok, messages_sent}}, state) when is_reference(task_ref) do
    Logger.debug("Successfully sent messages to Kafka")

    {_sent_messages, remaining_messages} = :queue.split(messages_sent, state.queue)
    emit_queue_telemetry(state, :queue.len(remaining_messages))

    Process.send_after(self(), :send, state.send_throttle_time)
    {:noreply, %{state | queue: remaining_messages, send_ref: nil}}
  end

  # We ran into an error sending messages to Kafka. We don't clear the queue,
  # and we try again.
  @doc false
  def handle_info({task_ref, error}, state) when is_reference(task_ref) do
    case error do
      {:error, :timeout} ->
        Logger.error("Hit timeout when sending messages to Kafka")

      anything_else ->
        Logger.error("Error when sending messages to Kafka", error: inspect(anything_else))
    end

    Process.send_after(self(), :send, state.send_throttle_time)
    {:noreply, %{send_ref: nil}}
  end

  @doc false
  def handle_info(_, state), do: {:noreply, state}

  # A simple request to add more messages to the queue. Nothing fancy here.
  @doc false
  def handle_cast({:queue, messages}, state) do
    new_queue = :queue.join(state.queue, :queue.from_list(messages))
    emit_queue_telemetry(state, :queue.len(new_queue))

    Process.send_after(self(), :send, state.send_throttle_time)
    {:noreply, %{state | queue: new_queue}}
  end

  # This callback is called when the GenServer is being closed. In this case
  # the queue is already empty so we have nothing to do.
  @doc false
  def terminate(_reason, %{queue: {[], []}} = state) do
    emit_queue_telemetry(state, 0)
    Logger.debug("Stopping Kafee async worker with empty queue")
  end

  # In this case, we still have messages to send. We attempt to send them
  # synchronously, and if we fail at that we output them to the logs for
  # developers to handle.
  @doc false
  def terminate(_reason, %{send_ref: nil} = state) do
    count = :queue.len(state.queue)
    Logger.info("Attempting to send #{count} messages to Kafka before terminate")
    terminate_send(state)
  end

  # In this case, we already have a request in flight, but we need to
  # make sure we get an ack back from it and send all remaining messages.
  def terminate(reason, state) do
    receive do
      {:ok, sent_message_count} ->
        {_sent_messages, remaining_messages} = :queue.split(sent_message_count, state.queue)
        emit_queue_telemetry(state, :queue.len(remaining_messages))
        terminate(reason, %{state | queue: remaining_messages, send_ref: nil})

      _ ->
        terminate(reason, %{state | send_ref: nil})
    after
      state.send_timeout ->
        terminate(reason, %{state | send_ref: nil})
    end
  end

  @spec terminate_send(t()) :: :ok
  defp terminate_send(state) do
    case send_messages(state) do
      {:ok, 0} ->
        Logger.info("Successfully sent all remaining messages to Kafka before termination")
        emit_queue_telemetry(state, 0)
        :ok

      {:ok, sent_message_count} ->
        Logger.debug("Successfully sent #{sent_message_count} messages to Kafka before termination")
        {_sent_messages, remaining_messages} = :queue.split(sent_message_count, state.queue)
        emit_queue_telemetry(state, :queue.len(remaining_messages))
        terminate_send(%{state | queue: remaining_messages})

      anything_else ->
        Logger.error("Error when sending messages to Kafka before termination", error: inspect(anything_else))

        for message <- :queue.to_list(state.queue) do
          Logger.error("Unsent Kafka message", message: message)
        end

        :ok
    end
  rescue
    err ->
      Logger.error("""
      An exception was raised trying to send the remaining messages to Kafka before termination:

      #{Exception.format(:error, err)}
      """)

      for message <- :queue.to_list(state.queue) do
        Logger.error("Unsent Kafka message", message: message)
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

  @spec emit_queue_telemetry(t(), non_neg_integer()) :: :ok
  defp emit_queue_telemetry(state, count) do
    :telemetry.execute([:kafee, :queue], %{count: count}, %{
      topic: state.topic,
      partition: state.partition
    })
  end

  @spec send_messages(t()) :: {:ok, sent_count :: pos_integer()} | term()
  defp send_messages(state) do
    messages = build_message_batch(state.queue)
    messages_length = length(messages)

    if messages_length == 0 do
      {:ok, 0}
    else
      Logger.debug("Sending #{messages_length} messages to Kafka")

      :telemetry.span(
        [:kafee, :produce],
        %{
          count: messages_length,
          topic: state.topic,
          partition: state.partition
        },
        fn ->
          with {:ok, call_ref} <-
                 :brod.produce(state.brod_client_id, state.topic, state.partition, :undefined, messages),
               :ok <- :brod.sync_produce_request(call_ref, state.send_timeout) do
            {{:ok, messages_length}, %{}}
          end
        end
      )
    end
  end

  # We batch matches til we get close to the `max.request.size`
  # limit in Kafka. This ensures we send the max amount of data per
  # request without causing errors.
  @spec build_message_batch(:queue.queue()) :: [:brod.message_set()]
  defp build_message_batch(queue) do
    {batch_bytes, batch_messages} =
      Enum.reduce_while(:queue.to_list(queue), {0, []}, fn message, {bytes, batch} ->
        # I know that `:erlang.external_size` won't match what we actually
        # send, but it should be under the limit that would cause Kafka errors
        case bytes + :erlang.external_size(message) do
          total_bytes when total_bytes <= @max_request_size ->
            {:cont, {total_bytes, [message | batch]}}

          _ ->
            {:halt, {bytes, batch}}
        end
      end)

    batch_messages = Enum.reverse(batch_messages)

    Logger.debug("Creating batch of #{batch_bytes} bytes", messages: batch_messages)

    batch_messages
  end
end
