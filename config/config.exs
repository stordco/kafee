import Config

config :logger, :console,
  level: :warning,
  metadata: [:data, :error, :partition, :ref, :topic]

config :opentelemetry,
  traces_exporter: :none

config :opentelemetry, :processors, [
  {:otel_simple_processor, %{}}
]
