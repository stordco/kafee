import Config

config :logger, :console, level: :warn

config :tesla, adapter: Tesla.Mock
