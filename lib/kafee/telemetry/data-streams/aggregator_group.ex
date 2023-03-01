defmodule Kafee.Telemetry.DataStreams.AggregatorGroup do
  @moduledoc """
  This is very similar to the `Kafee.Telemetry.DataStreams.StatsPoint`, but
  this is used purely in the `Kafee.Telemetry.DataStreams.Aggregator`.
  """

  alias DogSketch.SimpleDog
  alias Kafee.Telemetry.DataStreams.{AggregatorPoint, StatsPoint}

  @sketch_opts [error: 0.01]

  defstruct service: "",
            edge_tags: [],
            hash: 0,
            parent_hash: 0,
            pathway_latency: DogSketch.SimpleDog.new(@sketch_opts),
            edge_latency: DogSketch.SimpleDog.new(@sketch_opts)

  @typedoc """
  Aggregated data from multiple single Kafka message points. This
  is unique to the hash and parent hash (making a single pathway),
  but aggregates the pathway and edge latency.
  """
  @type t :: %__MODULE__{
          service: String.t(),
          edge_tags: [String.t()],
          hash: non_neg_integer(),
          parent_hash: non_neg_integer(),
          pathway_latency: map(),
          edge_latency: map()
        }

  @doc """
  Creates a new aggregate stats point.
  """
  @spec new(AggregatorPoint.t()) :: t()
  def new(%AggregatorPoint{edge_tags: edge_tags, parent_hash: parent_hash, hash: hash}) do
    %__MODULE__{
      edge_tags: edge_tags,
      parent_hash: parent_hash,
      hash: hash
    }
  end

  @doc """
  Adds a single points latency stats to the given aggregate point. If a map of
  groups is given, we lookup the correct one via the point hash and add to it.
  """
  @spec add(%{required(non_neg_integer()) => t()} | t(), AggregatorPoint.t()) :: t()
  def add(%__MODULE__{} = group, %AggregatorPoint{pathway_latency: pathway_latency, edge_latency: edge_latency}) do
    normalized_pathway_latency = max(pathway_latency / 1_000_000_000, 0)
    normalized_edge_latency = max(edge_latency / 1_000_000_000, 0)

    Map.merge(group, %{
      pathway_latency: SimpleDog.insert(group.pathway_latency, normalized_pathway_latency),
      edge_latency: SimpleDog.insert(group.edge_latency, normalized_edge_latency)
    })
  end

  def add(groups, point) do
    Map.update(groups, point.hash, new(point), fn group -> add(group, point) end)
  end

  @doc """
  Creates a `Kafee.Telemetry.DataStreams.StatsPoint`.
  """
  @spec to_stats_point(t(), String.t()) :: StatsPoint.t()
  def to_stats_point(%__MODULE__{} = data, timestamp_type) do
    %StatsPoint{
      service: data.service,
      edge_tags: data.edge_tags,
      hash: data.hash,
      parent_hash: data.parent_hash,
      pathway_latency: data.pathway_latency,
      edge_latency: data.edge_latency,
      timestamp_type: timestamp_type
    }
  end
end
