defmodule Kafee.Telemetry.DataStreams.StatsPayload do
  @moduledoc """
  Encoding and decoding helper functions for Datadog data stream
  stats payloads.

  StatsPayload stores client computed stats.
  """

  alias Kafee.Telemetry.DataStreams.StatsBucket

  defstruct env: "",
            service: "",
            primary_tag: "",
            stats: [],
            tracer_version: "1.0.0",
            lang: "Elixir"

  @type t() :: %__MODULE__{
          env: String.t(),
          service: String.t(),
          primary_tag: String.t(),
          stats: [StatsBucket.t()],
          tracer_version: String.t(),
          lang: String.t()
        }

  @doc """
  Changes the struct to a string keyed map that DataDog
  expects.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = data) do
    %{
      "Env" => data.env,
      "Service" => data.service,
      "PrimaryTag" => data.primary_tag,
      "Stats" => Enum.map(data.stats, &StatsBucket.to_map/1),
      "TracerVersion" => data.tracer_version,
      "Lang" => data.lang
    }
  end

  @doc """
  Changes a Datadog typed map to an Elixir struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    struct(__MODULE__,
      env: Map.get(map, "Env", ""),
      service: Map.get(map, "Service", ""),
      primary_tag: Map.get(map, "PrimaryTag", ""),
      stats: map |> Map.get("Stats", []) |> Enum.map(&StatsBucket.from_map/1),
      tracer_version: Map.get(map, "TracerVersion", ""),
      lang: Map.get(map, "Lang", "Elixir")
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
