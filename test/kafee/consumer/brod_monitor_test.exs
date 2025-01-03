defmodule Kafee.Consumer.BrodMonitorTest do
  use Kafee.BrodCase
  alias Kafee.Consumer.{Adapter, BrodMonitor}

  setup do
    spy(Kafee.Consumer.Adapter)
    on_exit(fn -> restore(Kafee.Consumer.Adapter) end)

    spy(Datadog.DataStreams.Integrations.Kafka)
    on_exit(fn -> restore(Datadog.DataStreams.Integrations.Kafka) end)
  end

  describe "get_consumer_lag/5" do
    test "should correctly return consumer lags per partition", %{brod_client_id: brod_client_id, topic: topic} do
      message =
        Kafee.BrodApi.generate_consumer_message(
          consumer_group: "my-consumer-group",
          topic: "test-topic",
          partition: 2,
          offset: 4
        )

      BroadwayMonitor.get_consumer_lag(brod_client_id, endpoints, topic, consumer_group_id, options \\ [])
      :ok = Adapter.push_message(MyConsumer, @consumer_options, message)
    end
  end
end
