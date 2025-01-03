defmodule Kafee.Consumer.BrodMonitor do
  @moduledoc """
  Utility module for monitoring Broadway - covering consumer lags

  In addition to existing telemetry data, it is highly beneficial to track the consumer lag as well.

  As a refresher, a “consumer lag” equals the latest message offset that has reached
  the broker (i.e. last message published) minus last message
  that has been consumed for the consumer group.
  Calculating this per partition is the goal.

  """
  require Logger

  def get_consumer_lag(client_id, endpoints, topic, consumer_group_id, options \\ []) do
    # Step 1: Get partitions and latest offsets

    partitions = get_partitions(endpoints, topic, options)
    latest_offsets = get_latest_offsets(endpoints, topic, partitions, options)
    # Step 2: Get committed offsets and filter to current node
    {:ok, committed_offsets} = get_committed_offsets(client_id, consumer_group_id)
    topic_offsets_map = Enum.find(committed_offsets, %{partitions: []}, &(&1.name == topic))
    node_name = Atom.to_string(Node.self())

    filtered_committed_offsets =
      limit_committed_offset_data_to_current_node(topic_offsets_map, node_name)

    # Step 3: Calculate lag
    calculate_lag(latest_offsets, filtered_committed_offsets)
  end

  def limit_committed_offset_data_to_current_node(committed_offsets_map, node_name) do
    committed_offsets_per_partitions = committed_offsets_map.partitions

    offsets_on_node =
      Enum.filter(committed_offsets_per_partitions, fn %{metadata: metadata} ->
        String.contains?(metadata, node_name)
      end)

    %{committed_offsets_map | partitions: offsets_on_node}
  end

  def get_committed_offsets(client_id, consumer_group_id) do
    :brod.fetch_committed_offsets(client_id, consumer_group_id)
  end

  def get_partitions(endpoints, topic, options \\ []) do
    case :brod.get_metadata(endpoints, [topic], options) do
      {:ok, %{topics: [%{partitions: partitions}]}} ->
        Enum.map(partitions, fn %{partition_index: id} -> id end)

      _ ->
        []
    end
  end

  def get_latest_offsets(endpoints, topic, partitions, options) do
    Enum.map(partitions, fn partition ->
      case :brod.resolve_offset(endpoints, topic, partition, :latest, options) do
        {:ok, offset} ->
          {partition, offset}

        {:error, reason} ->
          Logger.warning("Error getting offset for partition #{partition}: #{inspect(reason)}")
          {partition, 0}
      end
    end)
  end

  def committed_offsets_by_partition(committed_offsets) do
    committed_offsets
    |> Enum.map(fn %{partition_index: partition, committed_offset: committed_offset} ->
      {partition, committed_offset}
    end)
    |> Enum.into(%{})
  end

  defp calculate_lag(latest_offsets, %{partitions: _} = topic_offsets) do
    partition_to_committed_offsets_map = committed_offsets_by_partition(topic_offsets.partitions)

    partition_to_latest_offsets_map = Enum.into(latest_offsets, %{})

    lags_map =
      Map.intersect(partition_to_latest_offsets_map, partition_to_committed_offsets_map, fn _k, latest, committed ->
        latest - committed
      end)

    {:ok, lags_map}
  end
end
