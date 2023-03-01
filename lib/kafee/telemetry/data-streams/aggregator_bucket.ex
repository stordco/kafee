defmodule Kafee.Telemetry.DataStreams.AggregatorBucket do
  @moduledoc """
  This is very similar to the `Kafee.Telemetry.DataStreams.StatsBucket`, but
  this is used purely in the `Kafee.Telemetry.DataStreams.Aggregator`.
  """

  alias Kafee.Telemetry.DataStreams.{AggregatorGroup, StatsBucket}

  @bucket_duration 10 * 1_000 * 1_000 * 1_000

  defstruct points: %{},
            latest_commit_offsets: %{},
            latest_produce_offsets: %{},
            start: 0,
            duration: @bucket_duration

  @typedoc """
  Aggregated data from multiple single Kafka message points. This
  is unique to the hash and parent hash (making a single pathway),
  but aggregates the pathway and edge latency.
  """
  @type t :: %__MODULE__{
          points: %{non_neg_integer() => AggregatorGroup.t()},
          latest_commit_offsets: %{non_neg_integer() => non_neg_integer()},
          latest_produce_offsets: %{partition_key() => non_neg_integer()},
          start: non_neg_integer(),
          duration: non_neg_integer()
        }

  @type partition_key :: %{
          partition: non_neg_integer(),
          topic: String.t()
        }

  @doc """
  Aligns the timestamp to one that represents the bucket start.
  """
  @spec align_timestamp(non_neg_integer()) :: non_neg_integer()
  def align_timestamp(timestamp) do
    timestamp - rem(timestamp, @bucket_duration)
  end

  @doc """
  Creates a new aggregator bucket based on the aligned start timestamp.
  """
  @spec new(non_neg_integer()) :: t()
  def new(aligned_timestamp) do
    %__MODULE__{start: aligned_timestamp}
  end

  @doc """
  Modifies a bucket based on the aligned start time. If the bucket does not
  exist, it will be created and added to the list.
  """
  @spec modify(%{required(non_neg_integer()) => t()}, non_neg_integer(), (t() -> t())) :: %{
          required(non_neg_integer()) => t()
        }
  def modify(buckets, aligned_timestamp, fun) do
    Map.update(buckets, aligned_timestamp, new(aligned_timestamp), fun)
  end

  @doc """
  Checks if the bucket is currently within it's active duration.
  """
  @spec currently_active?(t()) :: boolean()
  def currently_active?(bucket) do
    now = DateTime.to_unix(DateTime.utc_now(), :nanosecond)
    # Extra time added just in case.
    bucket.start > now + @bucket_duration + 1_000_000
  end

  @doc """
  Creates a `Kafee.Telemetry.DataStreams.StatsBucket`.
  """
  @spec to_stats_bucket(t(), String.t()) :: StatsBucket.t()
  def to_stats_bucket(%__MODULE__{} = data, timestamp_type) do
    %StatsBucket{
      start: data.start,
      duration: data.duration,
      stats: Enum.map(data.points, &AggregatorGroup.to_stats_point(&1, timestamp_type)),
      # TODO: Backlogs
      backlogs: []
    }
  end
end
