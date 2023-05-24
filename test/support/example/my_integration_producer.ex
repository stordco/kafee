defmodule MyIntegrationProducer do
  @moduledoc """
  A producer used for integration testing.
  """

  use Kafee.Producer,
    producer_backend: Kafee.Producer.AsyncBackend,
    partition_fun: :random
end
