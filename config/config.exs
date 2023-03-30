import Config

config :logger, :console,
  level: :warn,
  metadata: [:data, :error, :partition, :ref, :topic]
