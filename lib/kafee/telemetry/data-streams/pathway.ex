defmodule Kafee.Telemetry.DataStreams.Pathway do
  @moduledoc """
  A pathway is used to monitor how payloads are sent across
  different services.

  An example pathway would be:

  ```
  service A -- edge 1 --> service B -- edge 2 --> service C
  ```

  So it's a bunch of services (we also call them "nodes) connected via edges.
  As the payload is sent around, we save the start time (start of service A),
  and the start time of the previous service. This allows us to measure the
  latency of each edge, as well as the latency from origin of any service.

  See the [data-streams-go][DSG] package for more details.

  [DSG]: https://github.com/DataDog/data-streams-go/blob/main/datastreams/pathway.go
  """

  alias Kafee.Telemetry.DataStreams.{Aggregator, AggregatorPoint}

  @hashable_edge_tags ["event_type", "exchange", "group", "topic", "type", "partition"]

  defstruct hash: 0,
            pathway_start: 0,
            edge_start: 0

  @type t :: %__MODULE__{
          hash: non_neg_integer(),
          pathway_start: non_neg_integer(),
          edge_start: non_neg_integer()
        }

  @doc """
  Merges multiple pathways into one. The current implementation samples
  one resulting pathway. A future implementation could be more clever
  and actually merge the pathways.
  """
  @spec merge(list(t())) :: t()
  def merge(pathways \\ []) do
    if Enum.empty?(pathways) do
      %__MODULE__{}
    else
      Enum.random(pathways)
    end
  end

  @doc """
  Hashes all data for a pathway.

  ## Examples

      iex> node_hash("service-1", "env", "d:1", ["edge-1"])
      2071821778175304604

  """
  @spec node_hash(String.t(), String.t(), String.t(), list(String.t())) :: integer()
  def node_hash(service, env, primary_tag, edge_tags \\ []) do
    edge_tags =
      edge_tags
      |> Enum.filter(fn tag ->
        case String.split(tag, ":") do
          [key, _value] when key in @hashable_edge_tags -> true
          _ -> false
        end
      end)
      |> Enum.sort()

    ([service, env, primary_tag] ++ edge_tags)
    |> Enum.join("")
    |> FNV.FNV1.hash64()
  end

  @doc """
  Hashes together a node and parent hash

  ## Examples

      iex> pathway_hash(2071821778175304604, 17210443572488294574)
      2003974475228685984

  """
  @spec pathway_hash(integer(), integer()) :: integer()
  def pathway_hash(node_hash, parent_hash) do
    FNV.FNV1.hash64(:binary.encode_unsigned(node_hash, :little) <> :binary.encode_unsigned(parent_hash, :little))
  end

  @doc """
  Creates a new pathway struct.
  """
  @spec new_pathway(list(String.t())) :: t()
  @spec new_pathway(non_neg_integer(), list(String.t())) :: t()
  def new_pathway(edge_tags) do
    DateTime.utc_now()
    |> DateTime.to_unix(:nanosecond)
    |> new_pathway(edge_tags)
  end

  def new_pathway(now, edge_tags) do
    set_checkpoint(
      %__MODULE__{
        hash: 0,
        pathway_start: now,
        edge_start: now
      },
      now,
      edge_tags
    )
  end

  @doc """
  Sets a checkpoint on a pathway.
  """
  @spec set_checkpoint(t(), list(String.t())) :: t()
  @spec set_checkpoint(t(), non_neg_integer(), list(String.t())) :: t()
  def set_checkpoint(pathway, edge_tags) do
    set_checkpoint(pathway, DateTime.to_unix(DateTime.utc_now(), :nanosecond), edge_tags)
  end

  def set_checkpoint(pathway, now, edge_tags) do
    config = Application.get_env(:kafee, :telemetry, [])
    service = Keyword.get(config, :service, "unnamed-elixir-service")
    env = Keyword.get(config, :env, "")
    primary_tag = Keyword.get(config, :primary_tag, "")

    child = %__MODULE__{
      hash: pathway_hash(node_hash(service, env, primary_tag, edge_tags), pathway.hash),
      pathway_start: pathway.pathway_start,
      edge_start: now
    }

    now = DateTime.to_unix(DateTime.utc_now(), :nanosecond)

    Aggregator.add(%AggregatorPoint{
      edge_tags: edge_tags,
      parent_hash: pathway.hash,
      hash: child.hash,
      timestamp: now,
      pathway_latency: now - pathway.pathway_start,
      edge_latency: now - pathway.edge_start
    })

    child
  end
end
