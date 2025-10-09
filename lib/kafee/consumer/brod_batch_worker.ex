defmodule Kafee.Consumer.BrodBatchWorker do
  # This module is responsible for being the brod group subscriber
  # worker for batch processing. It receives message sets from :brod
  # and handles batch accumulation, processing, and acknowledgment.

  @moduledoc false

  @behaviour :brod_group_subscriber_v2

  require Logger
  require Record

  Record.defrecord(
    :kafka_message,
    Record.extract(:kafka_message, from_lib: "brod/include/brod.hrl")
  )

  Record.defrecord(
    :kafka_message_set,
    Record.extract(:kafka_message_set, from_lib: "brod/include/brod.hrl")
  )

  defmodule State do
    @moduledoc false
    defstruct [
      :consumer,
      :group_id,
      :options,
      :adapter_options,
      :partition,
      :topic,
      :current_batch,
      :batch_start_time,
      :batch_bytes,
      :in_flight_batches,
      :dlq_producer,
      :retry_counts
    ]
  end

  @doc false
  @impl :brod_group_subscriber_v2
  def init(info, config) do
    state = %State{
      consumer: config.consumer,
      group_id: info.group_id,
      options: config.options,
      adapter_options: config.adapter_options,
      partition: info.partition,
      topic: info.topic,
      current_batch: [],
      batch_start_time: nil,
      batch_bytes: 0,
      in_flight_batches: 0,
      dlq_producer: nil,
      retry_counts: %{}
    }

    unless function_exported?(state.consumer, :handle_batch, 1) do
      raise ArgumentError, """
      Consumer module #{inspect(state.consumer)} must implement handle_batch/1 when using batch mode.

      Please add the following to your consumer module:

        @impl Kafee.Consumer
        def handle_batch(messages) do
          # Process the batch of messages
          # Return :ok, {:ok, failed_messages}, or {:error, reason}
        end
      """
    end

    # Initialize DLQ producer if configured
    state = maybe_init_dlq_producer(state)

    {:ok, state}
  end

  @doc false
  @impl :brod_group_subscriber_v2
  @spec handle_message(:brod.message_set(), State.t()) ::
          {:ok, :commit | {:commit, :brod.offset()}, State.t()}
          | {:ok, :ack, State.t()}
  def handle_message(
        kafka_message_set(topic: _topic, partition: _partition, messages: messages),
        %State{} = state
      ) do
    new_messages =
      Enum.map(messages, fn msg ->
        kafka_msg = kafka_message(msg)

        %{
          key: kafka_msg[:key],
          value: kafka_msg[:value],
          offset: kafka_msg[:offset],
          timestamp: kafka_msg[:ts],
          headers: kafka_msg[:headers]
        }
      end)

    process_messages_with_batching(state, new_messages)
  end

  defp process_messages_with_batching(state, []), do: {:ok, :ack, state}

  defp process_messages_with_batching(state, [message | rest]) do
    state = accumulate_single_message(state, message)

    if should_process_batch?(state) do
      case process_and_commit_batch(state) do
        {:ok, new_state, commit_offset} ->
          # Process the batch and continue with remaining messages
          if commit_offset do
            process_messages_with_batching(new_state, rest)
          else
            # Don't commit, but continue processing
            process_messages_with_batching(new_state, rest)
          end

        {:error, new_state} ->
          # Don't commit on error, stop processing
          {:ok, :ack, new_state}
      end
    else
      process_messages_with_batching(state, rest)
    end
  end

  defp accumulate_single_message(%State{current_batch: []} = state, message) do
    start_time = System.monotonic_time(:millisecond)
    message_size = calculate_message_size(message)

    :telemetry.execute(
      [:kafee, :batch, :started],
      %{message_count: 1, batch_bytes: message_size},
      %{
        topic: state.topic,
        partition: state.partition,
        consumer_group: state.group_id,
        consumer: state.consumer
      }
    )

    %{state | current_batch: [message], batch_start_time: start_time, batch_bytes: message_size}
  end

  defp accumulate_single_message(%State{} = state, message) do
    message_size = calculate_message_size(message)

    :telemetry.execute(
      [:kafee, :batch, :accumulated],
      %{
        message_count: 1,
        total_messages: length(state.current_batch) + 1,
        total_bytes: state.batch_bytes + message_size
      },
      %{
        topic: state.topic,
        partition: state.partition,
        consumer_group: state.group_id,
        consumer: state.consumer
      }
    )

    %{state | current_batch: state.current_batch ++ [message], batch_bytes: state.batch_bytes + message_size}
  end

  defp calculate_message_size(message) do
    byte_size(message.value || "") + byte_size(message.key || "")
  end

  defp should_process_batch?(%State{adapter_options: opts} = state) do
    length(state.current_batch) >= opts[:batch_size] ||
      state.batch_bytes >= opts[:max_batch_bytes] ||
      batch_timeout_exceeded?(state)
  end

  defp batch_timeout_exceeded?(%State{batch_start_time: nil}), do: false

  defp batch_timeout_exceeded?(%State{batch_start_time: start_time, adapter_options: opts}) do
    elapsed = System.monotonic_time(:millisecond) - start_time
    elapsed >= opts[:batch_timeout]
  end

  defp process_and_commit_batch(%State{current_batch: []} = state) do
    {:ok, state, nil}
  end

  defp process_and_commit_batch(%State{} = state) do
    if state.in_flight_batches >= state.adapter_options[:max_in_flight_batches] do
      Process.sleep(100)
      process_and_commit_batch(state)
    else
      kafee_messages =
        Enum.map(state.current_batch, fn msg ->
          %Kafee.Consumer.Message{
            key: msg.key,
            value: msg.value,
            topic: state.topic,
            partition: state.partition,
            offset: msg.offset,
            consumer_group: state.group_id,
            timestamp: DateTime.from_unix!(msg.timestamp, :millisecond),
            headers: msg.headers
          }
        end)

      state = %{state | in_flight_batches: state.in_flight_batches + 1}

      batch_start_time = System.monotonic_time()

      :telemetry.execute(
        [:kafee, :batch, :process_start],
        %{
          message_count: length(kafee_messages),
          batch_bytes: state.batch_bytes,
          ack_strategy: state.adapter_options[:ack_strategy]
        },
        %{
          topic: state.topic,
          partition: state.partition,
          consumer_group: state.group_id,
          consumer: state.consumer
        }
      )

      result = process_batch_sync(kafee_messages, state)

      batch_duration = System.monotonic_time() - batch_start_time

      case result do
        {:ok, failed_messages} ->
          :telemetry.execute(
            [:kafee, :batch, :process_end],
            %{
              duration: batch_duration,
              message_count: length(kafee_messages),
              failed_count: length(failed_messages),
              success_count: length(kafee_messages) - length(failed_messages)
            },
            %{
              topic: state.topic,
              partition: state.partition,
              consumer_group: state.group_id,
              consumer: state.consumer,
              ack_strategy: state.adapter_options[:ack_strategy]
            }
          )

          # Handle failed messages and get updated state with retry counts
          state_after_failures = handle_failed_messages(failed_messages, state)

          # Determine commit strategy based on failures and ack_strategy
          commit_offset = determine_commit_offset(state_after_failures, kafee_messages, failed_messages)

          # Reset batch state but preserve retry counts
          new_state = %{
            state_after_failures
            | current_batch: [],
              batch_start_time: nil,
              batch_bytes: 0,
              in_flight_batches: state.in_flight_batches - 1
          }

          {:ok, new_state, commit_offset}

        {:error, reason} ->
          Logger.error("Batch processing failed: #{inspect(reason)}")

          :telemetry.execute(
            [:kafee, :batch, :process_error],
            %{
              duration: batch_duration,
              message_count: length(kafee_messages)
            },
            %{
              topic: state.topic,
              partition: state.partition,
              consumer_group: state.group_id,
              consumer: state.consumer,
              error: reason
            }
          )

          new_state = %{state | in_flight_batches: state.in_flight_batches - 1}

          # For batch errors, handle as if all messages failed
          # This ensures retry tracking works correctly
          state_after_failures = handle_failed_messages(kafee_messages, new_state)

          # Clear the batch but don't commit
          final_state = %{
            state_after_failures
            | current_batch: [],
              batch_start_time: nil,
              batch_bytes: 0
          }

          case state.adapter_options[:ack_strategy] do
            :all_or_nothing ->
              Logger.warning("Batch processing failed with all_or_nothing strategy, not committing",
                topic: state.topic,
                partition: state.partition,
                batch_size: length(kafee_messages)
              )

            :best_effort ->
              Logger.warning("Batch processing failed with best_effort strategy",
                topic: state.topic,
                partition: state.partition,
                batch_size: length(kafee_messages)
              )

            :last_successful ->
              Logger.warning("Batch processing failed with last_successful strategy",
                topic: state.topic,
                partition: state.partition,
                batch_size: length(kafee_messages)
              )
          end

          {:ok, final_state, nil}
      end
    end
  end

  defp process_batch_sync(messages, state) do
    try do
      case state.adapter_options[:ack_strategy] do
        :all_or_nothing ->
          process_batch_all_or_nothing(messages, state)

        :best_effort ->
          process_batch_best_effort(messages, state)

        :last_successful ->
          process_batch_last_successful(messages, state)
      end
    rescue
      exception ->
        {:error, exception}
    end
  end

  defp process_batch_all_or_nothing(messages, state) do
    case state.consumer.handle_batch(messages) do
      :ok -> {:ok, []}
      {:ok, failed_messages} when failed_messages == [] -> {:ok, []}
      {:ok, _failed_messages} -> {:error, :partial_failure}
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_batch_best_effort(messages, state) do
    # For best_effort, track individual failures
    case state.consumer.handle_batch(messages) do
      :ok ->
        {:ok, []}

      {:ok, failed_messages} ->
        {:ok, failed_messages}

      {:error, _reason} ->
        # If batch handler fails, consider all messages failed
        {:ok, messages}
    end
  end

  defp process_batch_last_successful(messages, state) do
    # Process messages in order, stop at first failure
    case state.consumer.handle_batch(messages) do
      :ok ->
        {:ok, []}

      {:ok, failed_messages} ->
        # Find where failures start
        {_succeeded, failed} = split_at_first_failure(messages, failed_messages)
        {:ok, failed}

      {:error, _reason} ->
        # If batch handler fails, consider all messages failed
        {:ok, messages}
    end
  end

  defp split_at_first_failure(messages, failed_messages) do
    failed_offsets = MapSet.new(failed_messages, & &1.offset)

    {succeeded, failed} =
      Enum.split_while(messages, fn message ->
        not MapSet.member?(failed_offsets, message.offset)
      end)

    {succeeded, failed}
  end

  defp handle_failed_messages([], state), do: state

  defp handle_failed_messages(failed_messages, state) do
    Enum.reduce(failed_messages, state, fn message, acc_state ->
      handle_single_failure(message, acc_state)
    end)
  end

  defp handle_single_failure(message, state) do
    # Check if DLQ is configured
    case state.adapter_options[:dead_letter_config] do
      nil ->
        # No DLQ, just log
        Logger.error("Message processing failed without DLQ configured",
          topic: message.topic,
          partition: message.partition,
          offset: message.offset
        )

        state

      dlq_config ->
        # Track retry count
        message_id = {message.topic, message.partition, message.offset}
        retry_count = Map.get(state.retry_counts, message_id, 0) + 1
        max_retries = dlq_config[:max_retries] || 3

        # Emit retry telemetry
        :telemetry.execute(
          [:kafee, :batch, :message_retry],
          %{
            retry_count: retry_count,
            max_retries: max_retries
          },
          %{
            topic: message.topic,
            partition: message.partition,
            offset: message.offset,
            consumer_group: state.group_id,
            consumer: state.consumer
          }
        )

        if retry_count >= max_retries do
          # Send to DLQ
          send_to_dlq(message, state, dlq_config, retry_count)
          # Remove from retry counts as it's going to DLQ
          new_retry_counts = Map.delete(state.retry_counts, message_id)
          %{state | retry_counts: new_retry_counts}
        else
          # Update retry count for next attempt
          new_retry_counts = Map.put(state.retry_counts, message_id, retry_count)

          Logger.warning("Message processing failed, retry #{retry_count}/#{max_retries}",
            topic: message.topic,
            partition: message.partition,
            offset: message.offset
          )

          %{state | retry_counts: new_retry_counts}
        end
    end
  end

  defp send_to_dlq(message, state, dlq_config, retry_count) do
    # Determine DLQ topic - either from dedicated config or shared producer default
    dlq_topic = dlq_config[:topic] || "default-dlq"

    # Build DLQ message with metadata headers
    dlq_headers = build_dlq_headers(message, state, retry_count)

    # Send to DLQ using brod directly
    dlq_start = System.monotonic_time()

    case send_dlq_message(state, dlq_topic, message, dlq_headers) do
      :ok ->
        # Emit DLQ success telemetry
        :telemetry.execute(
          [:kafee, :batch, :dlq_sent],
          %{
            duration: System.monotonic_time() - dlq_start,
            retry_count: retry_count
          },
          %{
            topic: message.topic,
            partition: message.partition,
            offset: message.offset,
            dlq_topic: dlq_topic,
            consumer_group: state.group_id,
            consumer: state.consumer
          }
        )

        Logger.info("Message sent to DLQ",
          topic: message.topic,
          partition: message.partition,
          offset: message.offset,
          dlq_topic: dlq_topic,
          retry_count: retry_count
        )

        # Call consumer's handle_dead_letter callback if available
        if function_exported?(state.consumer, :handle_dead_letter, 2) do
          state.consumer.handle_dead_letter(message, %{
            retry_count: retry_count,
            dlq_topic: dlq_topic
          })
        end

      {:error, reason} ->
        # Emit DLQ error telemetry
        :telemetry.execute(
          [:kafee, :batch, :dlq_error],
          %{
            duration: System.monotonic_time() - dlq_start,
            retry_count: retry_count
          },
          %{
            topic: message.topic,
            partition: message.partition,
            offset: message.offset,
            dlq_topic: dlq_topic,
            consumer_group: state.group_id,
            consumer: state.consumer,
            error: reason
          }
        )

        Logger.error("Failed to send message to DLQ: #{inspect(reason)}",
          topic: message.topic,
          partition: message.partition,
          offset: message.offset,
          dlq_topic: dlq_topic
        )
    end
  end

  defp build_dlq_headers(message, state, retry_count) do
    base_headers = %{
      "x-original-topic" => message.topic,
      "x-original-partition" => to_string(message.partition),
      "x-original-offset" => to_string(message.offset),
      "x-failure-timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "x-retry-count" => to_string(retry_count),
      "x-consumer-group" => state.group_id
    }

    # Merge with existing headers, converting to list format for brod
    existing_headers = Map.get(message, :headers, [])

    headers_map =
      if is_list(existing_headers) do
        Enum.into(existing_headers, %{}, fn {k, v} -> {to_string(k), to_string(v)} end)
      else
        existing_headers
      end

    Map.merge(headers_map, base_headers)
    |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp send_dlq_message(state, topic, message, headers) do
    case state.dlq_producer do
      {:shared, producer_name} ->
        # Use shared DLQ producer
        dlq_message = %{
          key: message.key,
          value: message.value,
          headers: headers,
          topic: topic
        }

        try do
          Kafee.DLQProducer.send_message(producer_name, topic, dlq_message)
        catch
          :exit, {:noproc, _} ->
            {:error, :dlq_producer_not_started}
        end

      {:dedicated, client_id} ->
        # Use dedicated brod client
        # Note: brod doesn't support headers in produce_sync/5
        # For now, we'll send without headers but log them
        Logger.debug("Sending to DLQ with headers", headers: headers)

        case :brod.produce_sync(client_id, topic, 0, message.key || "", message.value || "") do
          :ok -> :ok
          {:error, _} = error -> error
        end

      nil ->
        {:error, :no_dlq_producer}
    end
  end

  defp get_last_offset([]), do: nil

  defp get_last_offset(messages) do
    messages
    |> List.last()
    |> Map.get(:offset)
  end

  defp determine_commit_offset(%State{adapter_options: opts}, messages, failed_messages) do
    case opts[:ack_strategy] do
      :all_or_nothing ->
        # Only commit if no failures
        if failed_messages == [] do
          get_last_offset(messages)
        else
          nil
        end

      :best_effort ->
        # Always commit the last message, even with failures
        get_last_offset(messages)

      :last_successful ->
        # Commit up to the last successful message
        if failed_messages == [] do
          get_last_offset(messages)
        else
          # Find the last successful offset before any failure
          failed_offsets = MapSet.new(failed_messages, & &1.offset)

          last_successful =
            messages
            |> Enum.reverse()
            |> Enum.find(fn msg -> not MapSet.member?(failed_offsets, msg.offset) end)

          if last_successful, do: last_successful.offset, else: nil
        end
    end
  end

  defp maybe_init_dlq_producer(%State{adapter_options: opts} = state) do
    case opts[:dead_letter_config] do
      nil ->
        state

      dlq_config ->
        # Check if using shared producer or per-consumer configuration
        cond do
          # Using shared DLQ producer (recommended)
          producer = dlq_config[:producer] ->
            %{state | dlq_producer: {:shared, producer}}

          # Using per-consumer DLQ topic (legacy/advanced use)
          _topic = dlq_config[:topic] ->
            init_dedicated_dlq_producer(state, dlq_config)

          true ->
            Logger.warning("DLQ configured but no producer or topic specified")
            state
        end
    end
  end

  defp init_dedicated_dlq_producer(state, dlq_config) do
    # Initialize a dedicated brod client for this consumer's DLQ
    client_id = Module.concat([state.consumer, "DLQClient"])

    # Start the brod client with the same connection settings
    case :brod.start_client(
           [{state.options[:host], state.options[:port]}],
           client_id,
           _client_config =
             [
               sasl: state.options[:sasl],
               ssl: state.options[:ssl]
             ]
             |> Enum.reject(fn {_k, v} -> is_nil(v) end)
         ) do
      :ok ->
        Logger.info("Started dedicated DLQ producer client",
          client_id: client_id,
          dlq_topic: dlq_config[:topic]
        )

        %{state | dlq_producer: {:dedicated, client_id}}

      {:error, {:already_started, _pid}} ->
        # Client already started, just use it
        %{state | dlq_producer: {:dedicated, client_id}}

      {:error, reason} ->
        Logger.error("Failed to start DLQ producer client: #{inspect(reason)}",
          client_id: client_id
        )

        state
    end
  end

  # We'll need to handle timeouts differently since brod_group_subscriber_v2
  # doesn't support handle_info. Instead, we'll check timeout on each message.
end
