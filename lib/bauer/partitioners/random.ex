defmodule Bauer.Partitioner.Random do
  @moduledoc """
  Picks a random partition.
  """

  @behaviour Bauer.Partitioner

  def partition(count, _key) do
    :rand.uniform(count) - 1
  end
end
