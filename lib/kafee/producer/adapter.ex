defmodule Kafee.Producer.Adapter do
  @moduledoc """
  A simple interface to implement your own custom sending logic. An adapter
  has three callbacks it needs to implement. The first one is a simple
  `start_link/1` that starts the adapter process. This could be a `Supervisor`
  or `GenServer` or any other process. The second callback is for generating
  a partition for a given message. This usually relies on `:brod` to fetch
  the current partition count. The last callback does the actual sending
  of the message.

  Currently, Kafee has three built in modules:
  - `Kafee.Producer.AsyncAdapter`
  - `Kafee.Producer.SyncAdapter`
  - `Kafee.Producer.TestAdapter`

  ```mermaid
  sequenceDiagram
    participant P as MyProducer
    participant B as Kafee.Producer.Adapter

    P-->>+: start_link/2
    B-->-: {:ok, pid()}

    P->>+B: get_partitions/2
    B-->>-P: [1, 2, 3, 4]

    P-->>+B: produce/2
    B-->>-P: :ok
  ```
  """

  alias Kafee.Producer

  @doc """
  Starts the lower level library responsible for taking `t:Producer.Message.t/0` and
  sending them to Kafka.
  """
  @callback start_link(module(), Producer.options()) :: Supervisor.on_start()

  @doc """
  Returns a list of valid partitions for a producer.

  ## Examples

      iex> partitions(MyProducer, [])
      [1, 2, 3, 4]

  """
  @callback partitions(module(), Producer.options()) :: [Kafee.partition()]

  @doc """
  Sends all of the given messages to the adapter for sending.
  """
  @callback produce([Producer.Message.t()], module(), Producer.options()) :: :ok | {:error, term()}
end
