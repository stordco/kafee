defmodule Bauer.KafkaCase do
  @moduledoc """
  Helper functions when testing Bauer and real Kafka instances.
  """

  require Logger

  @doc """
  Returns a Keyword list of args you can provide a producer backend
  to get it to connect to a testing Kafka instance.
  """
  def kafka_credentials do
    [host: kafka_host(), port: kafka_port(), client_config: [query_api_versions: false]]
  end

  defp kafka_host do
    System.get_env("KAFKA_HOST", "localhost")
  end

  defp kafka_port do
    "KAFKA_PORT" |> System.get_env("9092") |> String.to_integer()
  end
end
