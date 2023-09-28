import Config

config :logger, :console,
  level: :warning,
  metadata: [:data, :error, :partition, :ref, :topic]
