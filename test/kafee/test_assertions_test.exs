defmodule Kafee.TestAssertionsTestModule do
  use Kafee.Producer,
    topic: "testing",
    producer_backend: Kafee.TestingProducerBackend

  def prepare(_topic, text, _opts) do
    %Kafee.Message{key: "test", value: text}
  end
end

defmodule Kafee.TestAssertionsTest do
  use ExUnit.Case, async: true

  import Kafee.TestAssertions

  setup do
    start_supervised!(Kafee.TestAssertionsTestModule)
    :ok
  end

  describe "assert_kafee_message_produced/0" do
    test "true on any message send" do
      assert :ok = Kafee.TestAssertionsTestModule.produce("one")
      assert_kafee_message_produced()
    end
  end

  describe "assert_kafee_message_produced/1" do
    test "true on function assert" do
      assert :ok = Kafee.TestAssertionsTestModule.produce("one")

      assert_kafee_message_produced(fn topic, message ->
        assert topic == "testing"
        assert message.key == "test"
        assert message.value == "one"
      end)
    end

    test "true on message assert" do
      assert :ok = Kafee.TestAssertionsTestModule.produce("one")
      assert_kafee_message_produced(%Kafee.Message{key: "test", value: "one"})
    end
  end

  describe "assert_kafee_message_produced/2" do
    test "true on message assert" do
      assert :ok = Kafee.TestAssertionsTestModule.produce("one")
      assert_kafee_message_produced("testing", %Kafee.Message{key: "test", value: "one"})
    end
  end
end
