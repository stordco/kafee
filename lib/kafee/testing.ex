defmodule Kafee.Testing do
  @moduledoc """
  This module holds a bunch of helper functions to be used
  when testing your application with Kafee.

  ## Testing Producer

  ### Setup

  To test a producer, you will first need to set the
  `producer_backend` module to `Kafee.Producer.TestBackend`.
  This stores all of the messages in local memory so you can
  assert them later.

  ### Assertions

  """

  @doc """
  Asserts that a `Kafee.Producer` sent a message that matches the
  given.

  ## Examples

      iex> assert_message_produced(MyProducer, %{
      ...>   key: "test-key",
      ...>   topic: "test-topic"
      ...> })
      true

  """
  defmacro assert_producer_message(producer, map) do
    assertion =
      Macro.escape(
        quote do
          assert_message_produced(unquote(producer), unquote(map))
        end,
        prune_metadata: true
      )

    quote do
      map = unquote(map)
      messages = Kafee.Testing.producer_messages(unquote(producer))

      keys =
        map
        |> Map.delete(:__struct__)
        |> Map.keys()

      in_list? =
        Enum.any?(messages, fn message ->
          Enum.all?(keys, fn key ->
            Map.get(message, key) == Map.get(map, key)
          end)
        end)

      if in_list? do
        true
      else
        raise ExUnit.AssertionError,
          args: [unquote(producer), unquote(map)],
          left: map,
          right: messages,
          expr: unquote(assertion),
          message: "Message matching the map given was not found"
      end
    end
  end

  @doc """
  Returns all of the messages that were sent via a producer.

  ## Examples

      iex> producer_messages(MyProducer)
      [%Kafee.Producer.Message{}]

  """
  def producer_messages(producer) do
    backend = Kafee.Producer.Backend.process_name(producer)
    GenServer.call(backend, :get)
  end
end