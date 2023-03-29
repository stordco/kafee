defmodule MyProducer do
  @moduledoc """
  An example producer used for testing and documentation.
  """

  use Kafee.Producer,
    producer_backend: Kafee.Producer.TestBackend,
    partition_fun: :random

  def publish(_type, messages), do: produce(messages)
end
