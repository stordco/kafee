defmodule Kafee.Producer.Backend do
  @moduledoc """
  A simple interface to implement your own custom sending logic. A backend
  has three callbacks it needs to implement. The first one is a simple
  `start_link/1` that starts the backend process. This could be a `Supervisor`
  or `GenServer` or any other process. The second callback is for generating
  a partition for a given message. This usually relies on `:brod` to fetch
  the current partition count. The last callback does the actual sending
  of the message.

  ```mermaid
  sequenceDiagram
    participant P as MyProducer
    participant B as Kafee.Producer.Backend

    P-->>+: start_link/1
    B-->-: {:ok, pid()}

    P->>+B: get_partition/2
    B-->>-P: {:ok, 2}

    P-->>+B: produce/2
    B-->>-P: :ok
  ```
  """

  alias Kafee.Producer.{Config, Message}

  @doc """
  Starts the backend process.
  """
  @callback start_link(Config.t()) :: :ignore | {:ok, pid()} | {:error, any()}

  @doc """
  Returns the partition number for a message. Usually relies on
  `:brod` to get the current partition count.

  ## Examples

      iex> partition(%Config{}, %Message{})
      {:ok, 1}

  """
  @callback partition(Config.t(), Message.t()) :: {:ok, :brod.partition()} | {:error, term()}

  @doc """
  Sends all of the given messages to the backend for sending.
  """
  @callback produce(Config.t(), [Message.t()]) :: :ok | {:error, term()}

  @doc """
  Creates a process atom name for a `Kafee.Producer` backend.

  ## Examples

      iex> process_name(MyProducer)
      MyProducer.Backend

  """
  @spec process_name(atom()) :: Supervisor.name()
  def process_name(producer) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(producer, Backend)
  end
end
