defmodule Kafee.Telemetry.DataStreams.StatsBucket do
  @moduledoc """
  Encoding and decoding helper functions for Datadog data stream
  stats bucket.

  StatsBucket specifies a set of stats computed over a duration.
  """

  alias Kafee.Telemetry.DataStreams.{Backlog, StatsPoint}

  # 10 seconds
  @duration 10 * 1_000_000_000

  defstruct start: 0,
            duration: @duration,
            stats: [],
            backlogs: []

  @type t() :: %__MODULE__{
          start: non_neg_integer(),
          duration: non_neg_integer(),
          stats: [StatsPoint.t()],
          backlogs: [Backlog.t()]
        }

  @doc """
  Changes the struct to a string keyed map that DataDog
  expects.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = data) do
    %{
      "Start" => data.start - rem(data.start, data.duration),
      "Duration" => data.duration,
      "Stats" => Enum.map(data.stats, &StatsPoint.to_map/1),
      "Backlogs" => Enum.map(data.backlogs, &Backlog.to_map/1)
    }
  end

  @doc """
  Changes a Datadog typed map to an Elixir struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    struct(__MODULE__,
      start: Map.get(map, "Start", 0),
      duration: Map.get(map, "Duration", 0),
      stats: map |> Map.get("Stats", []) |> Enum.map(&StatsPoint.from_map/1),
      backlogs: map |> Map.get("Backlogs", []) |> Enum.map(&Backlog.from_map/1)
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
