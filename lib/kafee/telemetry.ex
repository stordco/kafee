defmodule Kafee.Telemetry do
  @moduledoc """
  Kafee has built in Telemetry utilizing the `:telemetry` library, as well as
  the `:opentelemetry_api` library. This exports traces and metrics compatible
  with the Open Telemetry Kafka specifications.

    - [Metrics][Metrics]
    - [Traces][Traces]

  In addition to these standards, we also export [Datadog][Datadog] specific
  metrics and trace data to support [Data Streams Monitoring][DSM]. Because
  [Datadog][Datadog] does not officially support Elixir, we are reverse
  engineering the [data-streams-go][DSG] library.

  [Metrics]: https://opentelemetry.io/docs/reference/specification/metrics/semantic_conventions/instrumentation/kafka/
  [Traces]: https://opentelemetry.io/docs/reference/specification/trace/semantic_conventions/messaging/
  [Datadog]: https://www.datadoghq.com/
  [DSM]: https://docs.datadoghq.com/data_streams/#measure-end-to-end-pipeline-health-with-new-metrics
  [DSG]: https://github.com/DataDog/data-streams-go

  ## Telemetry Events

  - `[:kafee, :produce, :start]` - Starting to send a message to Kafka.
  - `[:kafee, :produce, :stop]` - Kafka acknowledged the message.
  - `[:kafee, :produce, :exception]` - An exception occurred sending a message to Kafka.

  These events will be emitted for the async backend, and sync backend, but
  _not_ the test backend. Each will include the topic and partition of the
  message being sent, as well as the count if you are using the async backend.

  The recommended collection of these metrics can be done via:

      summary("kafee.produce.stop.count",
        tags: [:topic, :partition]
      ),
      summary("kafee.produce.stop.duration",
        tags: [:topic, :partition],
        unit: {:native, :millisecond}
      ),
      summary("kafee.produce.exception.duration",
        tags: [:topic, :partition],
        unit: {:native, :millisecond}
      )
  """
end
