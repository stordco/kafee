defmodule Kafee.Telemetry.DataStreams.Http do
  @moduledoc """
  An HTTP client for Datadog data streams reporting. It uses
  `Tesla` to support multi library usage. By default this uses
  the `:httpc` adapter, but you probably don't want to be using
  that in production.
  """

  use Tesla

  @adapter {Tesla.Adapter.Httpc, []}
  @headers [
    {"Content-Type", "application/msgpack"},
    {"Content-Encoding", "gzip"},
    {"Datadog-Meta-Lang", "Elixir"},
    {"X-README", "Sorry if stuff is breaking ~ blake.kostner@stord.com"}
  ]

  def new(config \\ []) do
    client = Keyword.get(config, :http_adapter, @adapter)

    base_path =
      "http://" <> Keyword.get(config, :host, "localhost") <> ":" <> to_string(Keyword.get(config, :port, 8126))

    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, base_path},
        {Tesla.Middleware.Headers, @headers},
        {Tesla.Middleware.Compression, format: "gzip"},
        Tesla.Middleware.JSON,
        {Tesla.Middleware.Timeout, timeout: 2_000}
      ],
      client
    )
  end

  @doc """
  Sends msgpack binary to Datadog.
  """
  @spec send_pipeline_stats(Tesla.Client.t(), binary) :: :ok | {:error, any()}
  def send_pipeline_stats(client, stats) do
    case Tesla.post(client, "/v0.1/pipeline_stats", stats) do
      {:ok, %Tesla.Env{status: 202, body: %{"acknowledged" => true}}} -> :ok
      {:ok, %Tesla.Env{body: %{"error" => error}}} -> {:error, error}
      {:error, any} -> {:error, any}
    end
  end
end
