defmodule Kafee.Producer.TestBackend do
  @moduledoc """
  This is a `Kafee.Producer.Backend` used for in local ExUnit
  tests. It takes all messages and sends them to the testing
  pid for use by the `Kafee.Test` module.
  """

  @behaviour Kafee.Producer.Backend

  @doc false
  @impl Kafee.Producer.Backend
  def child_spec([_config]), do: nil

  @doc """
  This will always return 0 as the partition.
  """
  @impl Kafee.Producer.Backend
  def partition(_config, message) do
    partition_fun = :brod_utils.make_part_fun(message.partition_fun)
    partition_fun.(message.topic, 1, message.key, message.value)
  end

  @doc """
  Adds messages to the internal memory.
  """
  @impl Kafee.Producer.Backend
  def produce(%Kafee.Producer.Config{} = config, messages) do
    for message <- messages do
      send(config.test_process, {:kafee_message, message})
    end

    :ok
  end
end
