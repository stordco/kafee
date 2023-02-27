alias DogSketch.SimpleDog
alias Kafee.Telemetry.DataStreams.{Backlog, Http, StatsBucket, StatsPayload, StatsPoint}

defmodule I do
  def random(range \\ :high) do
    case range do
      :high -> :rand.uniform(10)
      :low -> :rand.uniform(1)
    end
  end

  def sketch(values \\ [5]) do
    Enum.reduce(values, SimpleDog.new(error: 0.01), fn value, dog ->
      SimpleDog.insert(dog, value)
    end)
  end

  def random_sketch(range \\ :high) do
    1..50
    |> Enum.map(fn _i -> random(range) end)
    |> sketch()
  end

  def payload(pathway, edge) do
    struct(StatsPayload,
      env: "dev",
      service: "kafka-test",
      primary_tag: "datacenter:blake",
      stats: [
        %StatsBucket{
          start: DateTime.utc_now() |> DateTime.to_unix(:nanosecond),
          stats: [
            %StatsPoint{
              service: "kafka-test",
              edge_tags: ["type:edge-1"],
              hash: 2,
              parent_hash: 1,
              pathway_latency: sketch([1, 5]),
              edge_latency: sketch([1, 2]),
              timestamp_type: "current"
            },
            %StatsPoint{
              service: "kafka-test",
              edge_tags: ["type:edge-1"],
              hash: 3,
              parent_hash: 1,
              pathway_latency: sketch([5]),
              edge_latency: sketch([2]),
              timestamp_type: "current"
            }
          ],
          backlogs: [%Backlog{
            tags: ["partition:1", "topic:topic1", "type:kafka_produce"],
            value: 15
          }]
        },
        %StatsBucket{
          start: DateTime.utc_now() |> DateTime.add(-5, :second) |> DateTime.to_unix(:nanosecond),
          stats: [
            %StatsPoint{
              service: "kafka-test",
              edge_tags: ["type:edge-1"],
              hash: 2,
              parent_hash: 1,
              pathway_latency: sketch([1, 5]),
              edge_latency: sketch([1, 2]),
              timestamp_type: "origin"
            },
            %StatsPoint{
              service: "kafka-test",
              edge_tags: ["type:edge-1"],
              hash: 3,
              parent_hash: 1,
              pathway_latency: sketch([5]),
              edge_latency: sketch([2]),
              timestamp_type: "origin"
            }
          ],
          backlogs: []
        }
      ]
    )
  end

  def random_payload() do
    pathway = random_sketch(:high)
    edge = random_sketch(:low)

    payload(pathway, edge)
  end

  def encode(payload) do
    with {:ok, encoded_payload} = StatsPayload.encode(payload) do
      encoded_payload
    end
  end

  def stream(max \\ 5) do
    client = Http.new()

    for _i <- 1..max do
      encoded_payload = encode(random_payload())
      Http.send_pipeline_stats(client, encoded_payload)
      Process.sleep(10_000)
    end

    :ok
  end
end
