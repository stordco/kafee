defmodule Kafee.Message do
  @moduledoc """
  A top level struct representing any message produced or handled via Kafee.
  This includes some fields needed for provisioning and producing messages like
  `partition_key` and `partitioner`, as well as fields we will only know when
  handling, like `offset`.
  """

  defstruct key: "",
            value: "",
            offset: 0,
            partition: 1,
            partition_key: "",
            partitioner: Kafee.Partitioner.Random,
            timestamp: nil,
            headers: []

  @type t() :: %__MODULE__{
          key: binary(),
          value: binary(),
          offset: non_neg_integer(),
          partition: pos_integer(),
          partition_key: binary(),
          partitioner: atom(),
          timestamp: DateTime.t() | nil,
          headers: list({binary(), binary()})
        }
end
