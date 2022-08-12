defmodule Bauer.ProducerTestModule do
  use Bauer.Producer,
    topic: "testing",
    producer_backend: Bauer.TestingProducerBackend

  def prepare(_topic, text, _opts) do
    %Bauer.Message{key: "test", value: text}
  end
end

defmodule Bauer.ProducerTest do
  use ExUnit.Case, async: true

  setup do
    start_supervised!(Bauer.ProducerTestModule)
    :ok
  end

  describe "produce/2" do
    test "sends a message to the producer" do
      assert :ok = Bauer.ProducerTestModule.produce("one")

      assert_received {:bauer_message, "testing",
                       %{
                         key: "test",
                         value: "one"
                       }}
    end

    test "sends multiple messages to the producer" do
      assert :ok = Bauer.ProducerTestModule.produce(["one", "two"])

      assert_received {:bauer_message, "testing",
                       %{
                         key: "test",
                         value: "one"
                       }}

      assert_received {:bauer_message, "testing",
                       %{
                         key: "test",
                         value: "two"
                       }}
    end
  end
end
