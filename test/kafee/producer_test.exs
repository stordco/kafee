defmodule Kafee.ProducerTestModule do
  use Kafee.Producer,
    topic: "testing",
    producer_backend: Kafee.TestingProducerBackend

  def prepare(_topic, text, _opts) do
    %Kafee.Message{key: "test", value: text}
  end
end

defmodule Kafee.ProducerTest do
  use ExUnit.Case, async: true

  setup do
    start_supervised!(Kafee.ProducerTestModule)
    :ok
  end

  describe "produce/2" do
    test "sends a message to the producer" do
      assert :ok = Kafee.ProducerTestModule.produce("one")

      assert_received {:kafee_message, "testing",
                       %{
                         key: "test",
                         value: "one"
                       }}
    end

    test "sends multiple messages to the producer" do
      assert :ok = Kafee.ProducerTestModule.produce(["one", "two"])

      assert_received {:kafee_message, "testing",
                       %{
                         key: "test",
                         value: "one"
                       }}

      assert_received {:kafee_message, "testing",
                       %{
                         key: "test",
                         value: "two"
                       }}
    end
  end
end
