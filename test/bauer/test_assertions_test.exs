defmodule Bauer.TestAssertionsTestModule do
  use Bauer.Producer,
    topic: "testing",
    producer_backend: Bauer.TestingProducerBackend

  def prepare(_topic, text, _opts) do
    %Bauer.Message{key: "test", value: text}
  end
end

defmodule Bauer.TestAssertionsTest do
  use ExUnit.Case, async: true

  import Bauer.TestAssertions

  setup do
    start_supervised!(Bauer.TestAssertionsTestModule)
    :ok
  end

  describe "assert_bauer_message_produced/0" do
    test "true on any message send" do
      assert :ok = Bauer.TestAssertionsTestModule.produce("one")
      assert_bauer_message_produced()
    end
  end

  describe "assert_bauer_message_produced/1" do
    test "true on function assert" do
      assert :ok = Bauer.TestAssertionsTestModule.produce("one")

      assert_bauer_message_produced(fn topic, message ->
        assert topic == "testing"
        assert message.key == "test"
        assert message.value == "one"
      end)
    end

    test "true on message assert" do
      assert :ok = Bauer.TestAssertionsTestModule.produce("one")
      assert_bauer_message_produced(%Bauer.Message{key: "test", value: "one"})
    end
  end

  describe "assert_bauer_message_produced/2" do
    test "true on message assert" do
      assert :ok = Bauer.TestAssertionsTestModule.produce("one")
      assert_bauer_message_produced("testing", %Bauer.Message{key: "test", value: "one"})
    end
  end
end
