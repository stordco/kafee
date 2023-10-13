defmodule Kafee.Producer.AsyncWorker do
  # A simple GenServer for every topic * partition in Kafka. It holds an
  # erlang `:queue` and sends messages every so often. On process close, we
  # attempt to send all messages to Kafka, and in the unlikely event we can't
  # we write all messages to the logs.

  @moduledoc false

  use GenServer,
    shutdown: :timer.seconds(25)

  import Kafee, only: [is_offset: 1]

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Datadog.DataStreams.Integrations.Kafka, as: DDKafka
  alias Kafee.Producer.Message

  @data_streams_propagator_key Datadog.DataStreams.Propagator.propagation_key()

  defmodule State do
    @moduledoc false

    defstruct [
      :brod_client_id,
      :max_request_bytes,
      :partition,
      :queue,
      :throttle_ms,
      :send_task,
      :send_timeout,
      :topic
    ]

    @type t :: %__MODULE__{
            brod_client_id: :brod.client_id(),
            max_request_bytes: pos_integer(),
            partition: Kafee.partition(),
            queue: :queue.queue(),
            throttle_ms: pos_integer(),
            send_task: Task.t() | nil,
            send_timeout: pos_integer(),
            topic: Kafee.topic()
          }
  end

  @type opts :: [
          brod_client_id: :brod.client(),
          max_request_bytes: pos_integer(),
          partition: Kafee.partition(),
          send_timeout: pos_integer(),
          throttle_ms: pos_integer(),
          topic: Kafee.topic()
        ]

  ## Public-ish API

  @doc false
  @spec start_link(opts()) :: GenServer.on_start()
  def start_link(opts) do
    brod_client_id = Keyword.fetch!(opts, :brod_client_id)
    topic = Keyword.fetch!(opts, :topic)
    partition = Keyword.fetch!(opts, :partition)

    GenServer.start_link(__MODULE__, opts, name: process_name(brod_client_id, topic, partition))
  end

  @doc false
  @spec queue(pid(), [Message.t()]) :: :ok
  def queue(pid, messages) do
    GenServer.cast(pid, {:queue, messages})
  end

  @doc false
  @spec process_name(:brod.client(), Kafee.topic(), Kafee.partition()) :: GenServer.name()
  def process_name(module, topic, partition) do
    {:via, Registry, {Kafee.Registry, {module, :worker, topic, partition}}}
  end

  ## Server API

  @doc false
  @spec init(opts()) :: {:ok, State.t()}
  def init(opts) do
    Process.flag(:trap_exit, true)

    brod_client_id = Keyword.fetch!(opts, :brod_client_id)
    max_request_bytes = Keyword.fetch!(opts, :max_request_bytes)
    topic = Keyword.fetch!(opts, :topic)
    partition = Keyword.fetch!(opts, :partition)
    throttle_ms = Keyword.fetch!(opts, :throttle_ms)
    send_timeout = Keyword.fetch!(opts, :send_timeout)

    Logger.metadata(topic: topic, partition: partition)

    {:ok,
     %State{
       brod_client_id: brod_client_id,
       max_request_bytes: max_request_bytes,
       partition: partition,
       queue: :queue.new(),
       throttle_ms: throttle_ms,
       send_task: nil,
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
  def handle_info(:send, %{send_task: nil} = state) do
    send_task = Task.async(fn -> send_messages(state) end)
    {:noreply, %{state | send_task: send_task}}
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
  def handle_info({task_ref, {:ok, messages_sent, offset}}, %{send_task: %{ref: task_ref}} = state) do
    Logger.debug("Successfully sent messages to Kafka")
    if is_offset(offset), do: DDKafka.track_produce(state.topic, state.partition, offset)
    {_sent_messages, remaining_messages} = :queue.split(messages_sent, state.queue)
    emit_queue_telemetry(state, :queue.len(remaining_messages))

    Process.send_after(self(), :send, state.throttle_ms)
    {:noreply, %{state | queue: remaining_messages}}
  end

  @doc false
  def handle_info({_task_ref, {:error, {:producer_down, :noproc}}}, state) do
    Logger.debug("The brod producer process is currently down. Waiting for it to come back online")
    Process.send_after(self(), :send, 10_000)
    {:noreply, state}
  end

  # We ran into an error sending messages to Kafka. We don't clear the queue,
  # and we try again.
  @doc false
  def handle_info({task_ref, error}, %{queue: queue, send_task: %{ref: task_ref}} = state) do
    sent_messages = build_message_batch(queue, state.max_request_bytes)

    state =
      case error do
        {:error, {:producer_down, {:not_retriable, {_, _, _, _, :message_too_large}}}}
        when length(sent_messages) == 1 ->
          Logger.error("Message in queue is too large", data: sent_messages)
          %{state | queue: :queue.drop(queue)}

        {:error, {:producer_down, {:not_retriable, {_, _, _, _, :message_too_large}}}} ->
          new_max_request_bytes = max(state.max_request_bytes - 1024, 500_000)

          Logger.error(
            "The configured `max_request_bytes` is larger than the Kafka cluster allows. Adjusting to #{new_max_request_bytes} bytes"
          )

          %{state | max_request_bytes: new_max_request_bytes}

        {:error, {:producer_down, {:not_retriable, _}}} ->
          Logger.error(
            "Last sent batch is not retriable. Dropping the head of the queue and retrying",
            data: sent_messages
          )

          %{state | queue: :queue.drop(queue)}

        {:error, :timeout} ->
          Logger.error("Hit timeout when sending messages to Kafka")
          state

        anything_else ->
          Logger.error("Error when sending messages to Kafka", error: inspect(anything_else))
          state
      end

    Process.send_after(self(), :send, state.throttle_ms)
    {:noreply, state}
  end

  # The Task finished successfully. We also received a message above
  # that does the actual processing. Now we just clear the send_task.
  @doc false
  def handle_info({:DOWN, task_ref, :process, _pid, :normal}, %{send_task: %{ref: task_ref}} = state) do
    {:noreply, %{state | send_task: nil}}
  end

  # The Task crashed trying to send messages. Major failure.
  # Requeue and try again.
  @doc false
  def handle_info({:DOWN, task_ref, :process, _pid, reason}, %{send_task: %{ref: task_ref}} = state) do
    Logger.error("Crash when sending messages to Kafka", error: inspect(reason))
    Process.send_after(self(), :send, state.throttle_ms)
    {:noreply, %{state | send_task: nil}}
  end

  # The next two function heads occur if we receive a message from a process
  # that is not currently sending messages to Kafka. This is a major bug
  # as it breaks our order guarantee.
  @doc false
  def handle_info({ref, data}, state) when is_reference(ref) do
    Logger.critical("Data from an unknown process", ref: inspect(ref), data: inspect(data))
    {:noreply, state}
  end

  @doc false
  def handle_info({:DOWN, ref, _, _pid, reason}, state) when is_reference(ref) do
    Logger.critical("Crash from an unknown process", ref: inspect(ref), error: inspect(reason))
    {:noreply, state}
  end

  @doc false
  def handle_info(_, state), do: {:noreply, state}

  # A simple request to add more messages to the queue. Nothing fancy here.
  @doc false
  def handle_cast({:queue, messages}, state) do
    new_queue = :queue.join(state.queue, :queue.from_list(messages))
    emit_queue_telemetry(state, :queue.len(new_queue))

    Process.send_after(self(), :send, state.throttle_ms)
    {:noreply, %{state | queue: new_queue}}
  end

  # This callback is called when the GenServer is being closed. In this case
  # the queue is already empty and we aren't sending messages, so we have
  # nothing to do.
  @doc false
  def terminate(_reason, %{send_task: nil, queue: {[], []}} = state) do
    emit_queue_telemetry(state, 0)
    Logger.debug("Stopping Kafee async worker with empty queue")
  end

  # In this case, we still have messages to send. We attempt to send them
  # synchronously, and if we fail at that we output them to the logs for
  # developers to handle.
  @doc false
  def terminate(_reason, %{send_task: nil} = state) do
    count = :queue.len(state.queue)
    Logger.info("Attempting to send #{count} messages to Kafka before terminate")
    terminate_send(state)
  end

  # In this case, we already have a request in flight, but we need to
  # make sure we get an ack back from it and send all remaining messages.
  def terminate(reason, %{send_task: %{ref: ref}} = state) do
    receive do
      {^ref, {:ok, sent_message_count, offset}} ->
        if is_offset(offset), do: DDKafka.track_produce(state.topic, state.partition, offset)
        {_sent_messages, remaining_messages} = :queue.split(sent_message_count, state.queue)
        emit_queue_telemetry(state, :queue.len(remaining_messages))
        terminate(reason, %{state | queue: remaining_messages, send_task: nil})

      {^ref, error} ->
        Logger.error("Crash when sending messages to Kafka", error: inspect(error))
        terminate(reason, %{state | send_task: nil})
    after
      state.send_timeout ->
        terminate(reason, %{state | send_task: nil})
    end
  end

  @spec terminate_send(State.t()) :: :ok
  defp terminate_send(state) do
    case send_messages(state) do
      {:ok, 0, offset} ->
        Logger.info("Successfully sent all remaining messages to Kafka before termination")
        if is_offset(offset), do: DDKafka.track_produce(state.topic, state.partition, offset)
        emit_queue_telemetry(state, 0)
        :ok

      {:ok, sent_message_count, offset} ->
        Logger.debug("Successfully sent #{sent_message_count} messages to Kafka before termination")
        if is_offset(offset), do: DDKafka.track_produce(state.topic, state.partition, offset)
        {_sent_messages, remaining_messages} = :queue.split(sent_message_count, state.queue)
        emit_queue_telemetry(state, :queue.len(remaining_messages))
        terminate_send(%{state | queue: remaining_messages})

      anything_else ->
        Logger.error("Error when sending messages to Kafka before termination", error: inspect(anything_else))

        for message <- :queue.to_list(state.queue) do
          Logger.error("Unsent Kafka message", data: message)
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
        Logger.error("Unsent Kafka message", data: message)
      end

      :ok
  end

  @spec emit_queue_telemetry(State.t(), non_neg_integer()) :: :ok
  defp emit_queue_telemetry(state, count) do
    :telemetry.execute([:kafee, :queue], %{count: count}, %{
      topic: state.topic,
      partition: state.partition
    })
  end

  @spec send_messages(State.t()) :: {:ok, sent_count :: pos_integer(), offset :: integer() | nil} | term()
  defp send_messages(state) do
    messages = build_message_batch(state.queue, state.max_request_bytes)
    messages_length = length(messages)

    if messages_length == 0 do
      {:ok, 0, nil}
    else
      Logger.debug("Sending #{messages_length} messages to Kafka")

      span_name = messages |> Enum.at(0) |> Message.get_otel_span_name()
      span_attributes = Message.get_otel_span_attributes(messages)

      Tracer.with_span span_name, %{kind: :client, attributes: span_attributes} do
        messages = normalize_messages(messages)

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
                 {:ok, offset} <- :brod.sync_produce_request_offset(call_ref, state.send_timeout) do
              {{:ok, messages_length, offset}, %{}}
            else
              res -> {res, %{}}
            end
          end
        )
      end
    end
  end

  @spec normalize_messages([Message.t()]) :: [Message.t()]
  defp normalize_messages(messages) do
    messages
    |> Enum.map(fn message ->
      if Message.has_header?(message, @data_streams_propagator_key),
        do: message,
        else: Datadog.DataStreams.Integrations.Kafka.trace_produce(message)
    end)
    |> Enum.map(&Map.take(&1, [:key, :value, :headers]))
  end

  # We batch matches til we get close to the `max.request.size`
  # limit in Kafka. This ensures we send the max amount of data per
  # request without causing errors.
  @spec build_message_batch(:queue.queue(), pos_integer()) :: [Message.t()]
  defp build_message_batch(queue, max_request_bytes) do
    {batch_bytes, batch_messages} =
      queue
      |> :queue.to_list()
      |> Enum.reduce_while({0, []}, fn message, {bytes, batch} ->
        # I know that `:erlang.external_size` won't match what we actually
        # send, but it should be under the limit that would cause Kafka errors
        kafka_message = Map.take(message, [:key, :value, :headers])

        case bytes + :erlang.external_size(kafka_message) do
          total_bytes when batch == [] ->
            {:cont, {total_bytes, [message]}}

          total_bytes when total_bytes <= max_request_bytes ->
            {:cont, {total_bytes, [message | batch]}}

          _ ->
            {:halt, {bytes, batch}}
        end
      end)

    batch_messages = Enum.reverse(batch_messages)

    Logger.debug("Creating batch of #{batch_bytes} bytes", data: batch_messages)

    batch_messages
  end
end
