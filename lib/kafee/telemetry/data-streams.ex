defmodule Kafee.Telemetry.DataStreams do
  @moduledoc """
  This is a Kafee Telemetry module designed to interface with DataDog's
  data streams system.

  ## Configuration

  Configuration can be done via the global `Kafee` application configuration
  like so:

      config :kafee, :data_streams,
        enabled: true,
        host: "localhost",
        http_adapter: {Tesla.Adapter.Finch, []},
        port: 8126

  """
end
