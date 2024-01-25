defmodule MyProducer do
  @moduledoc """
  An example producer used for testing and documentation.
  """

  use Kafee.Producer,
    adapter: nil,
    topic: "test-topic",
    partition_fun: :random

  def publish(_type, messages), do: produce(messages)
end
