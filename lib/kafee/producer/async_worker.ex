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

  defstruct [
    :brod_client_id,
    :partition,
    :queue,
    :send_count,
    :send_count_max,
    :send_interval,
    :send_interval_ref,
    :send_ref,
    :send_timeout,
    :send_timeout_ref,
    :telemetry_produce_start_time,
    :telemetry_produce_ref,
    :topic
  ]

  @type t :: %__MODULE__{
          brod_client_id: :brod.client_id(),
          partition: :brod.partition(),
          queue: :queue.queue(),
          send_count: non_neg_integer(),
          send_count_max: pos_integer(),
          send_interval: pos_integer(),
          send_interval_ref: reference() | nil,
          send_ref: :brod.call_ref() | nil,
          send_timeout: pos_integer(),
          send_timeout_ref: reference() | nil,
          telemetry_produce_start_time: integer() | nil,
          telemetry_produce_ref: reference() | nil,
          topic: :brod.topic()
        }

  @type opts :: [
          brod_client_id: :brod.client(),
          topic: :brod.topic(),
          partition: :brod.partition(),
          send_count_max: pos_integer(),
          send_interval: pos_integer() | nil,
          send_timeout: pos_integer() | nil
        ]

  @doc false
  @spec init(opts()) :: {:ok, t()}
  def init(opts) do
    Process.flag(:trap_exit, true)

    brod_client_id = Keyword.fetch!(opts, :brod_client_id)
    topic = Keyword.fetch!(opts, :topic)
    partition = Keyword.fetch!(opts, :partition)
    send_count_max = Keyword.get(opts, :send_count_max, 100)
    send_interval = Keyword.get(opts, :send_interval, :timer.seconds(2))
    send_timeout = Keyword.get(opts, :send_timeout, :timer.seconds(10))

    send_interval_ref = Process.send_after(self(), :send, send_interval)

    Logger.metadata(topic: topic, partition: partition)

    {:ok,
     %__MODULE__{
       brod_client_id: brod_client_id,
       partition: partition,
       queue: :queue.new(),
       send_count: 0,
       send_count_max: send_count_max,
       send_interval: send_interval,
       send_interval_ref: send_interval_ref,
       send_ref: nil,
       send_timeout: send_timeout,
       send_timeout_ref: nil,
       telemetry_produce_start_time: nil,
       telemetry_produce_ref: nil,
       topic: topic
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
    telemetry_produce_start_time = :erlang.monotonic_time()
    telemetry_produce_ref = :erlang.make_ref()

    {send_messages, _remaining_messages} =
      if :queue.len(state.queue) > state.send_count_max,
        do: :queue.split(state.queue, state.send_count_max),
        else: {state.queue, :queue.new()}

    messages = :queue.to_list(send_messages)
    messages_count = length(messages)

    state = %{
      state
      | send_count: messages_count,
        telemetry_produce_start_time: telemetry_produce_start_time,
        telemetry_produce_ref: telemetry_produce_ref
    }

    try do
      {:ok, send_ref} = :brod.produce(state.brod_client_id, state.topic, state.partition, :undefined, messages)

      :telemetry.execute(
        [:kafee, :produce, :start],
        %{monotonic_time: telemetry_produce_start_time, system_time: :erlang.system_time()},
        %{
          count: messages_count,
          telemetry_span_context: telemetry_produce_ref,
          topic: state.topic,
          partition: state.partition
        }
      )

      send_timeout_ref = Process.send_after(self(), :send_timeout, state.send_timeout)

      {:noreply,
       %{
         state
         | send_ref: send_ref,
           send_timeout_ref: send_timeout_ref
       }}
    rescue
      err in MatchError ->
        emit_produce_end_telemetry(state, :exception, %{
          kind: err.kind,
          reason: :exception,
          stacktrace: __STACKTRACE__
        })

        Logger.warn("""
          Unable to send message to Kafka because the `:brod_producer` is not found.
          This usually indicates that you are using the `Kafee.Producer.AsyncWorker`
          directly without setting `auto_state_producers` to `true` in when creating
          your `:brod_client` instance.

          #{Exception.format(:error, err)}
        """)

        send_interval_ref = Process.send_after(self(), :send, state.send_interval)

        {:noreply,
         %{
           state
           | send_count: 0,
             send_interval_ref: send_interval_ref,
             telemetry_produce_start_time: nil,
             telemetry_produce_ref: nil
         }}

      err in ArgumentError ->
        emit_produce_end_telemetry(state, :exception, %{
          kind: err.kind,
          reason: :exception,
          stacktrace: __STACKTRACE__
        })

        Logger.warn("""
          A runtime ArgumentError occurred while trying to send messages via `:brod`.
          This usually results in an infinite unrecoverable loop of errors, so we are
          going to terminate.

          #{Exception.format(:error, err)}
        """)

        {:stop, err,
         %{
           state
           | send_count: 0,
             telemetry_produce_start_time: nil,
             telemetry_produce_ref: nil
         }}

      err ->
        emit_produce_end_telemetry(state, :exception, %{
          kind: err.kind,
          reason: :exception,
          stacktrace: __STACKTRACE__
        })

        Logger.error("""
          Kafee received an unknown error when trying to send messages to Kafka.

          #{Exception.format(:error, err)}
        """)

        send_interval_ref = Process.send_after(self(), :send, state.send_interval)

        {:noreply,
         %{
           state
           | send_count: 0,
             send_interval_ref: send_interval_ref,
             telemetry_produce_start_time: nil,
             telemetry_produce_ref: nil
         }}
    end
  end

  # If we get here, we already have something in flight to Kafka, so we
  # do nothing and just keep on waiting.
  @doc false
  def handle_info(:send, state) do
    {:noreply, state}
  end

  # If this message is received, it means our last brod send has taken
  # too long to respond. This might mean the brod process crashed trying
  # to send the message, or some other part of the system is broken.
  # In this case, we want to retry sending the message.
  def handle_info(:send_timeout, state) do
    emit_produce_end_telemetry(state, :exception, %{
      kind: :error,
      reason: :timeout
    })

    Logger.info("Sending messages to Kafka timed out")

    send_interval_ref = Process.send_after(self(), :send, state.send_interval)

    {:noreply,
     %{
       state
       | send_count: 0,
         send_interval_ref: send_interval_ref,
         send_timeout_ref: nil,
         send_ref: nil,
         telemetry_produce_start_time: nil,
         telemetry_produce_ref: nil
     }}
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
    Process.cancel_timer(state.send_timeout_ref)

    emit_produce_end_telemetry(state, :stop)

    {_sent_messages, remaining_messages} = :queue.split(state.send_count, state.queue)
    emit_queue_telemetry(state, :queue.len(remaining_messages))

    send_interval_ref = Process.send_after(self(), :send, state.send_interval)

    {:noreply,
     %{
       state
       | queue: remaining_messages,
         send_count: 0,
         send_interval_ref: send_interval_ref,
         send_timeout_ref: nil,
         send_ref: nil,
         telemetry_produce_start_time: nil,
         telemetry_produce_ref: nil
     }}
  end

  # This handles the very rare (and dangerous) case where we get an
  # acknowledgement from Kafka, that doesn't match the last group of messages
  # we sent. This _shouldn't_ happen, but if it does, it means state
  # inconsistency in the form of duplicated messages in Kafka or missing
  # messages in Kafka.
  @doc false
  def handle_info({:brod_produce_reply, _send_ref, _offset, :brod_produce_req_acked}, state) do
    Logger.warn("Brod acknowledgement received that doesn't match internal records")
    send_interval_ref = Process.send_after(self(), :send, state.send_interval)
    {:noreply, %{state | send_interval_ref: send_interval_ref}}
  end

  # This handles the case if Brod sends a non successful acknowledgement.
  @doc false
  def handle_info({:brod_produce_reply, _send_ref, _offset, resp}, state) do
    Logger.warn("""
    Brod acknowledgement received, but it wasn't successful. Response:

    #{inspect(resp)}
    """)

    Process.cancel_timer(state.send_timeout_ref)
    send_interval_ref = Process.send_after(self(), :send, state.send_interval)
    {:noreply, %{state | send_interval_ref: send_interval_ref, send_timeout_ref: nil}}
  end

  # A simple request to add more messages to the queue. Nothing fancy here.
  @doc false
  def handle_cast({:queue, messages}, state) do
    new_queue = :queue.join(state.queue, :queue.from_list(messages))
    emit_queue_telemetry(state, :queue.len(new_queue))
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

    for messages <- Enum.chunk_every(:queue.to_list(state.queue), state.send_count_max) do
      :telemetry.span(
        [:kafee, :produce],
        %{count: length(messages), topic: state.topic, partition: state.partition},
        fn ->
          :ok = :brod.produce_sync(state.brod_client_id, state.topic, state.partition, :undefined, messages)
          {:ok, %{}}
        end
      )
    end

    emit_queue_telemetry(state, 0)
    Logger.info("Sent #{count} messages to Kafka before terminate")
  rescue
    err ->
      Logger.error("""
      Unable to send messages to Kafka:

      #{Exception.format(:error, err)}
      """)

      for message <- :queue.to_list(state.queue) do
        Logger.error("Unsent Kafka message", message: message)
      end
  end

  # In this case, we already have a request in flight, but we need to
  # make sure we get an ack back from it and send all remaining messages.
  def terminate(reason, %{send_ref: send_ref} = state) do
    Process.cancel_timer(state.send_timeout_ref)

    case :brod.sync_produce_request_offset(send_ref, state.send_timeout) do
      {:ok, _} ->
        emit_produce_end_telemetry(state, :stop)

        {_sent_messages, remaining_messages} = :queue.split(state.send_count, state.queue)
        emit_queue_telemetry(state, :queue.len(remaining_messages))

        terminate(reason, %{
          state
          | queue: remaining_messages,
            send_count: 0,
            send_interval_ref: nil,
            send_timeout_ref: nil,
            send_ref: nil
        })

      err ->
        emit_produce_end_telemetry(state, :exception, %{
          kind: :error,
          reason: :timeout
        })

        Logger.warn("""
        Error while trying to acknowledge last send messages. Retrying before exit.

        #{inspect(err)}
        """)

        terminate(reason, %{
          state
          | send_count: 0,
            send_interval_ref: nil,
            send_timeout_ref: nil,
            send_ref: nil
        })
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

  @spec emit_produce_end_telemetry(t(), atom(), map()) :: :ok
  defp emit_produce_end_telemetry(state, event, metadata \\ %{})
  defp emit_produce_end_telemetry(%{telemetry_produce_start_time: nil}, _event, _metadata), do: :ok
  defp emit_produce_end_telemetry(%{telemetry_produce_ref: nil}, _event, _metadata), do: :ok

  defp emit_produce_end_telemetry(
         %{telemetry_produce_start_time: start_time, telemetry_produce_ref: ref} = state,
         event,
         metadata
       ) do
    stop_time = :erlang.monotonic_time()

    :telemetry.execute(
      [:kafee, :produce, event],
      %{duration: stop_time - start_time, monotonic_time: stop_time},
      Map.merge(metadata, %{
        count: state.send_count,
        telemetry_span_context: ref,
        topic: state.topic,
        partition: state.partition
      })
    )
  end
end
