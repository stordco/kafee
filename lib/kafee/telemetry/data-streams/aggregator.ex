defmodule Kafee.Telemetry.DataStreams.Aggregator do
  @moduledoc """
  A GenServer to aggregate data points from data streams. Note, that while
  most of the data streams logic is a straight port from the
  [data-streams-go][DSG] library, this aggregator is written very differently
  than it's Golang counterpart.

  [DSG]: https://github.com/DataDog/data-streams-go/blob/main/datastreams/pathway.go
  """

  use GenServer

  require Logger

  alias Kafee.Telemetry.DataStreams.{AggregatorBucket, AggregatorGroup, AggregatorPoint, Http, StatsPayload}

  @send_interval 10_000

  @doc false
  def init(_opts) do
    if enabled?() do
      client_config = Application.get_env(:kafee, :data_streams, [])

      Process.send_after(self(), :send, @send_interval)

      {:ok,
       %{
         client: Http.new(client_config),
         ts_type_current_buckets: %{},
         ts_type_origin_buckets: %{}
       }}
    else
      :ignore
    end
  end

  @doc false
  def handle_info(:send, state) do
    payload = StatsPayload.new()

    {active_ts_type_current_buckets, past_ts_type_current_buckets} =
      split_with(state.ts_type_current_buckets, fn {_k, v} -> AggregatorBucket.currently_active?(v) end)

    {active_ts_type_origin_buckets, past_ts_type_origin_buckets} =
      split_with(state.ts_type_origin_buckets, fn {_k, v} -> AggregatorBucket.currently_active?(v) end)

    past_ts_type_current_buckets = Map.values(past_ts_type_current_buckets)
    past_ts_type_origin_buckets = Map.values(past_ts_type_origin_buckets)

    payload = Map.put(payload, :stats, past_ts_type_current_buckets ++ past_ts_type_origin_buckets)

    with {:ok, encoded_payload} <- StatsPayload.encode(payload),
         :ok <- Http.send_pipeline_stats(state.client, encoded_payload) do
      :telemetry.execute([:datadog, :datastreams, :aggregator, :flushed_payloads], %{count: 1})

      :telemetry.execute([:datadog, :datastreams, :aggregator, :flushed_buckets], %{
        count: length(past_ts_type_current_buckets) + length(past_ts_type_origin_buckets)
      })
    else
      {:error, reason} ->
        :telemetry.execute([:datadog, :datastreams, :aggregator, :flush_errors], %{count: 1})
        Logger.error("Unable to send DataDog DataStreams", error: reason)
    end

    Process.send_after(self(), :send, @send_interval)

    {:noreply,
     %{
       ts_type_current_buckets: active_ts_type_current_buckets,
       ts_type_origin_buckets: active_ts_type_origin_buckets
     }}
  end

  @doc false
  def handle_cast({:add_stat_point, point}, state) do
    current_bucket_time = AggregatorBucket.align_timestamp(point.timestamp)

    new_ts_type_current_buckets =
      AggregatorBucket.modify(state.ts_type_current_buckets, current_bucket_time, fn bucket ->
        AggregatorGroup.add(bucket.points, point)
      end)

    origin_bucket_time = AggregatorBucket.align_timestamp(point.timestamp - point.pathway_latency)

    new_ts_type_origin_buckets =
      AggregatorBucket.modify(state.ts_type_origin_buckets, origin_bucket_time, fn bucket ->
        AggregatorGroup.add(bucket.points, point)
      end)

    {:noreply,
     %{state | ts_type_current_buckets: new_ts_type_current_buckets, ts_type_origin_buckets: new_ts_type_origin_buckets}}
  end

  @doc """
  Starts the Data Streams aggregator.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds a stat point to the aggregator.
  """
  @spec add(AggregatorPoint.t()) :: :ok
  def add(point) do
    :telemetry.execute([:datadog, :datastreams, :aggregator, :payloads_in], %{count: 1})

    if enabled?() do
      GenServer.cast(__MODULE__, {:add_stat_point, point})
    else
      :ok
    end
  end

  defp enabled? do
    :kafee
    |> Application.get_env(:data_streams, [])
    |> Keyword.get(:enabled?, false)
  end

  @doc """
  Splits the `map` into two maps according to the given function `fun`.

  This function was taken from Elixir 1.15 for backwards support with older
  versions.
  """
  def split_with(map, fun) when is_map(map) and is_function(fun, 1) do
    iter = :maps.iterator(map)
    next = :maps.next(iter)

    do_split_with(next, [], [], fun)
  end

  defp do_split_with(:none, while_true, while_false, _fun) do
    {:maps.from_list(while_true), :maps.from_list(while_false)}
  end

  defp do_split_with({key, value, iter}, while_true, while_false, fun) do
    if fun.({key, value}) do
      do_split_with(:maps.next(iter), [{key, value} | while_true], while_false, fun)
    else
      do_split_with(:maps.next(iter), while_true, [{key, value} | while_false], fun)
    end
  end
end
