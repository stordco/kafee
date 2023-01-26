defmodule Kafee.Producer.MessageTest do
  use Kafee.KafkaCase

  alias Kafee.Producer.Message

  test "it can be json encoded with Jason" do
    assert {:ok, _} = Jason.encode(%Message{key: "test", value: "test"})
  end
end
