defmodule Kafee.Telemetry.DataStreams.StatsPoint do
  @moduledoc """
  Encoding and decoding helper functions for Datadog data stream
  backlog.

  StatsPoint contains a set of statistics grouped under various aggregation
  keys.
  """

  alias DogSketch.SimpleDog
  alias Kafee.Telemetry.DataStreams.{DDSketch, Store}

  @sketch_opts [error: 0.01]

  defstruct service: "",
            edge_tags: [],
            hash: 0,
            parent_hash: 0,
            pathway_latency: DogSketch.SimpleDog.new(@sketch_opts),
            edge_latency: DogSketch.SimpleDog.new(@sketch_opts),
            timestamp_type: "current"

  @type t :: %__MODULE__{
          service: String.t(),
          edge_tags: [String.t()],
          hash: non_neg_integer(),
          parent_hash: non_neg_integer(),
          pathway_latency: DogSketch.SimpleDog.t(),
          edge_latency: DogSketch.SimpleDog.t(),
          # "current" or "origin"
          timestamp_type: String.t()
        }

  @doc """
  Changes the struct to a string keyed map that DataDog
  expects.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = data) do
    %{
      "Service" => data.service,
      "EdgeTags" => data.edge_tags,
      "Hash" => data.hash,
      "ParentHash" => data.parent_hash,
      "PathwayLatency" => to_proto(data.pathway_latency),
      "EdgeLatency" => to_proto(data.edge_latency),
      "TimestampType" => data.timestamp_type
    }
  end

  # I have no clue what I'm doing with DogSketch or how Math works.
  # Sorry.
  def to_proto(%SimpleDog{} = dog) do
    Protobuf.encode(%DDSketch{
      mapping: %{
        gamma: dog.gamma,
        indexOffset: 0,
        interpolation: :NONE
      },
      positiveValues: %{
        binCounts: dog |> SimpleDog.to_list() |> Enum.map(fn {k, v} -> %Store.BinCountsEntry{key: v, value: k} end),
        #contiguousBinCounts: [1, 2, 3, 4],
        #contiguousBinIndexOffset: 2_147_483_647
      },
      negativeValues: %{
        contiguousBinCounts: nil
      },
      zeroCount: 0
    })
  end

  @doc """
  Changes a Datadog typed map to an Elixir struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    struct(__MODULE__,
      service: Map.get(map, "Service", ""),
      edge_tags: Map.get(map, "EdgeTags", ""),
      hash: Map.get(map, "Hash", 0),
      parent_hash: Map.get(map, "ParentHash", 0),
      # TODO: Decode these. Do we really need this?
      pathway_latency: Map.get(map, "PathwayLatency", DogSketch.SimpleDog.new(@sketch_opts)),
      edge_latency: Map.get(map, "EdgeLatency", DogSketch.SimpleDog.new(@sketch_opts)),
      timestamp_type: Map.get(map, "TimestampType", "current")
    )
  end

  @doc """
  Encodes data via MessagePack
  """
  @spec encode(t()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = data) do
    data
    |> to_map()
    |> MessagePack.pack(enable_string: true)
  end

  @doc """
  Decodes data via MessagePack
  """
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(binary) do
    with {:ok, data} <- MessagePack.unpack(binary, enable_string: true) do
      {:ok, from_map(data)}
    end
  end
end
