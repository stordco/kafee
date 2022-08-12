defmodule Kafee.TestAssertions do
  @moduledoc """
  A module to help you with application testing when using Kafee.

  ## Producer

  When testing a producer, you will first want to set the producer
  backend to `Kafee.TestingProducerBackend`.

  ### Examples

      iex> import Kafee.TestAssertions

      iex> MyApp.Producer.produce(%Kafee.Message{value: "testing"})

      # Assert any message was produced
      iex> assert_kafee_message_produced

      # Assert a message was produced by the actual message
      iex> assert_kafee_message_produced %Kafee.Message{value: "testing"}

      # Assert a message was produced by the topic and message
      iex> assert_kafee_message_produced "my-topic" %Kafee.Message{value: "testing"}

      # Assert a message satisfies a condition
      iex> assert_kafee_message_produced fn topic, message ->
        assert topic == "test-topic"
        assert message.value == "testing"
      end

  """

  import ExUnit.Assertions

  @doc """
  Asserts any Kafee message was produced.
  """
  def assert_kafee_message_produced do
    assert_received {:kafee_message, _, _}
  end

  def assert_kafee_message_produced(fun) when is_function(fun, 2) do
    assert_receive {:kafee_message, topic, message}
    assert fun.(topic, message)
  end

  def assert_kafee_message_produced(%Kafee.Message{} = message) do
    assert_receive {:kafee_message, _, ^message}
  end

  def assert_kafee_message_produced(topic, %Kafee.Message{} = message) do
    assert_receive {:kafee_message, ^topic, ^message}
  end
end
