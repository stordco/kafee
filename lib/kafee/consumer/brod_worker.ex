defmodule Kafee.Consumer.BrodWorker do
  # This module is responsible for being the brod group subscriber
  # worker. It gets started and handed messages from `:brod` to be
  # passed to `Kafee.Consumer`.

  @moduledoc false

  @behaviour :brod_group_subscriber_v2

  require Record

  Record.defrecord(
    :kafka_message,
    Record.extract(:kafka_message, from_lib: "brod/include/brod.hrl")
  )

  @doc false
  @impl :brod_group_subscriber_v2
  def init(info, config) do
    state =
      info
      |> Map.merge(config)
      |> Map.take([:consumer, :group_id, :options, :partition, :topic])

    {:ok, state}
  end

  @doc false
  @impl :brod_group_subscriber_v2
  @spec handle_message(:brod.message(), map()) :: {:ok, :commit, map()}
  def handle_message(
        message,
        %{
          consumer: consumer,
          group_id: group_id,
          options: options,
          partition: partition,
          topic: topic
        } = state
      ) do
    message = kafka_message(message)

    Kafee.Consumer.Adapter.push_message(consumer, options, %Kafee.Consumer.Message{
      key: message[:key],
      value: message[:value],
      topic: topic,
      partition: partition,
      offset: message[:offset],
      consumer_group: group_id,
      timestamp: DateTime.from_unix!(message[:ts], :millisecond),
      headers: message[:headers]
    })

    {:ok, :commit, state}
  end
end
