defmodule Kafee.Telemetry.DataStreams do
  @moduledoc """
  This is a Kafee Telemetry module designed to interface with DataDog's
  data streams system.

  ## Configuration

  Configuration can be done via the global `Kafee` application configuration
  like so:

      config :kafee, :data_streams,
        enabled?: true,
        host: "localhost",
        http_adapter: {Tesla.Adapter.Finch, []},
        port: 8126

      config :kafee, :telemetry,
        service: "my-service",
        env: "staging"

  """

  alias Kafee.Telemetry.DataStreams.{Pathway, Propagator}

  @propagation_key "dd-pathway-ctx"

  @doc """
  Adds trace data to an outgoing Kafka message. This will use any existing
  trace data from the OpenTelemetry dictionary to continue the stream.

  This function expects a map with a `:topic`, `:partition`, and `:headers`
  keys.

  ## Examples

      iex> trace_produce(%{topic: "test-topic", partition: 1, headers: []})
      # %{topic: "test-topic", partition: 1, headers: [{"dd-pathway-ctx", "abc123"}]}

  """
  @spec trace_produce_from_pathway(Pathway.t(), map()) :: {Pathway.t(), map()}
  def trace_produce_from_pathway(pathway, message) do
    edges =
      message
      |> Map.take([:topic, :partition])
      |> Map.merge(%{type: "kafka", direction: "out"})
      |> Enum.map(fn {k, v} -> to_string(k) <> ":" <> to_string(v) end)

    new_pathway = Pathway.set_checkpoint(pathway, edges)

    new_message =
      Map.update(message, :headers, [], fn headers ->
        headers
        |> Enum.reject(fn {k, _v} -> k == @propagation_key end)
        |> List.insert_at(-1, {@propagation_key, Propagator.encode(new_pathway)})
      end)

    {new_pathway, new_message}
  end

  @doc """
  Decodes a given Kafka message and adds information to the checkpoint.
  """
  @spec trace_consume_from_pathway(Pathway.t(), map(), String.t()) :: Pathway.t()
  def trace_consume_from_pathway(pathway, message, group) do
    pathway = get_pathway_from_header(pathway, Map.get(message, :headers, []))

    edges =
      message
      |> Map.take([:topic, :partition])
      |> Map.merge(%{type: "kafka", direction: "in", group: group})
      |> Enum.map(fn {k, v} -> to_string(k) <> ":" <> to_string(v) end)

    Pathway.set_checkpoint(pathway, edges)
  end

  defp get_pathway_from_header(pathway, headers) do
    {_key, header} = Enum.find(headers, {@propagation_key, nil}, fn {k, _v} -> k == @propagation_key end)

    if is_nil(header) do
      pathway
    else
      new_pathway = Propagator.decode(header)
      if is_nil(new_pathway), do: pathway, else: new_pathway
    end
  end
end
