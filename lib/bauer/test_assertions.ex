defmodule Bauer.TestAssertions do
  @moduledoc """
  A module to help you with application testing when using Bauer.

  ## Producer

  When testing a producer, you will first want to set the producer
  backend to `Bauer.TestingProducerBackend`.

  ### Examples

      iex> import Bauer.TestAssertions

      iex> MyApp.Producer.produce(%Bauer.Message{value: "testing"})

      # Assert any message was produced
      iex> assert_bauer_message_produced

      # Assert a message was produced by the actual message
      iex> assert_bauer_message_produced %Bauer.Message{value: "testing"}

      # Assert a message was produced by the topic and message
      iex> assert_bauer_message_produced "my-topic" %Bauer.Message{value: "testing"}

      # Assert a message satisfies a condition
      iex> assert_bauer_message_produced fn topic, message ->
        assert topic == "test-topic"
        assert message.value == "testing"
      end

  """

  import ExUnit.Assertions

  @doc """
  Asserts any bauer message was produced.
  """
  def assert_bauer_message_produced do
    assert_received {:bauer_message, _, _}
  end

  def assert_bauer_message_produced(fun) when is_function(fun, 2) do
    assert_receive {:bauer_message, topic, message}
    assert fun.(topic, message)
  end

  def assert_bauer_message_produced(%Bauer.Message{} = message) do
    assert_receive {:bauer_message, _, ^message}
  end

  def assert_bauer_message_produced(topic, %Bauer.Message{} = message) do
    assert_receive {:bauer_message, ^topic, ^message}
  end
end
