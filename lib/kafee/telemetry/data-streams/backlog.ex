defmodule Kafee.Telemetry.DataStreams.Backlog do
  @moduledoc """
  Encoding and decoding helper functions for Datadog data stream
  backloog.

  Backlog represents the size of a queue that hasn't been yet read by the
  consumer.
  """

  defstruct tags: [],
            value: 0

  @type t() :: %__MODULE__{
          tags: [String.t()],
          value: non_neg_integer()
        }

  @doc """
  Changes the struct to a string keyed map that DataDog
  expects.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = data) do
    %{
      "Tags" => data.tags,
      "Value" => data.value
    }
  end

  @doc """
  Changes a Datadog typed map to an Elixir struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    struct(__MODULE__,
      tags: Map.get(map, "Tags", []),
      value: Map.get(map, "Value", 0)
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
