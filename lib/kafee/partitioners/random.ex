defmodule Kafee.Partitioner.Random do
  @moduledoc """
  Picks a random partition.
  """

  @behaviour Kafee.Partitioner

  def partition(count, _key) do
    :rand.uniform(count) - 1
  end
end
