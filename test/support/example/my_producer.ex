defmodule MyProducer do
  @moduledoc """
  An example producer used for testing and documentation.
  """

  use Kafee.Producer,
    producer_adapter: Kafee.Producer.TestAdapter,
    partition_fun: :random

  def publish(_type, messages), do: produce(messages)
end
