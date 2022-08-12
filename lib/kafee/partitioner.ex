defmodule Kafee.Partitioner do
  @moduledoc """
  A behaviour to partition messages before sending to Kafka.
  """

  @typedoc """
  The number of partitions for a topic.
  """
  @type partition_count :: pos_integer

  @typedoc """
  Partition selected by the partitioning strategy.
  """
  @type partition :: non_neg_integer

  @callback partition(partition_count, key :: binary()) :: partition
end
