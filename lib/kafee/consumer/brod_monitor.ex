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

  @doc """
  Returns the consumer lag per consumer group per partition.
  A “consumer lag” equals the latest message offset that has reached
  the broker (i.e. last message published) minus last message
  that has been consumed for the consumer group.

  Options:
  * includes the connection options: [ssl: __, sasl: ___]
  * `:node_only`: boolean, default `false`. If `true`, filter to only partitions handled in node.
    - note: this is eventually going to be up to date. There is a lag due to reporting coming from `:brod.fetch_committed_offsets/2`'s metadata field
      reporting with delay on which node name the partition is at.

      What this means in an example:

      ```
      iex(warehouse@10.4.1.4)95> committed_offsets = BrodMonitor.get_committed_offsets(client_id, consumer_group_id)
      iex(warehouse@10.4.1.4)95> topic_offsets_map = Enum.find(committed_offsets, &(&1.name == topic))
      %{
        name: "wms-service--firehose",
        partitions: [
          %{
            # This metadata value could have a node name that is different from what shows up in Confluent cloud.
            # Either one could be the stale one - we don't know that deep.
            # The assumption is the value will eventually sync up to the correct node name.
            metadata: "+1/'warehouse@10.4.2.142'/<0.7948.0>",
            error_code: :no_error,
            partition_index: 2,
            committed_offset: 14052635
          },
          ...

      ```

  ## Note on how to use this information:

  In observations and tests, it seems fine to trigger a shutdown of the process `*.Broadway.ProducerSupervisor`
  on any of the node in the cluster - doing so will trigger a rebalancing across the cluster which will restart the supervisor tree, thereby
  kickstarting the consumption on the lagging partitions.

  Above comment is based on `Kafee.Consumer.BroadwayAdapter`, but since the functions are using `:brod`, it would be true
  also for `Kafee.Consumer.BrodAdapter`.

  """
  def get_consumer_lag(client_id, endpoints, topic, consumer_group_id, options \\ []) do
    # Step 1: Get partitions and latest offsets
    connection_options = Keyword.take(options, [:ssl, :sasl])
    partitions = get_partitions(endpoints, topic, connection_options)
    latest_offsets = get_latest_offsets(endpoints, topic, partitions, connection_options)

    # Step 2: Get committed offsets and filter to current node
    {:ok, committed_offsets} = get_committed_offsets(client_id, consumer_group_id)
    topic_offsets_map = Enum.find(committed_offsets, %{partitions: []}, &(&1.name == topic))
    node_name = Atom.to_string(Node.self())

    filtered_committed_offsets =
      if options[:node_only],
        do: limit_committed_offset_data_to_current_node(topic_offsets_map, node_name),
        else: topic_offsets_map

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

  defp calculate_lag(latest_offsets, %{partitions: _} = topic_offsets) do
    partition_to_committed_offsets_map = committed_offsets_by_partition(topic_offsets.partitions)

    partition_to_latest_offsets_map = Enum.into(latest_offsets, %{})

    common_map_keys =
      partition_to_latest_offsets_map
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(partition_to_committed_offsets_map)))
      |> MapSet.to_list()

    lags_map =
      partition_to_latest_offsets_map
      |> Map.merge(partition_to_committed_offsets_map, fn _k, latest, committed ->
        latest - committed
      end)
      |> Map.take(common_map_keys)

    {:ok, lags_map}
  end

  def committed_offsets_by_partition(committed_offsets) do
    committed_offsets
    |> Enum.map(fn %{partition_index: partition, committed_offset: committed_offset} ->
      {partition, committed_offset}
    end)
    |> Enum.into(%{})
  end
end
