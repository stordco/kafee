defmodule Kafee.TestSyncTest do
  use ExUnit.Case, async: false
  use Kafee.Test, shared: true

  alias Kafee.BrodApi

  @topic "kafee-test-sync-test"

  defmodule TestProducer do
    use Kafee.Producer,
      adapter: Kafee.Producer.TestAdapter,
      topic: "kafee-test-sync-test",
      partition_fun: :random
  end

  setup do
    start_supervised!(TestProducer)
    :ok
  end

  describe "assert_kafee_message/2" do
    test "asserts an exact matching message" do
      message = BrodApi.generate_producer_message(@topic)
      TestProducer.produce(message)
      assert_kafee_message(^message)
    end

    test "asserts a partial match" do
      message = BrodApi.generate_producer_message("a new test topic")
      TestProducer.produce(message)
      assert_kafee_message(%{topic: "a new test topic"})
    end

    test "asserts allow matching" do
      message = BrodApi.generate_producer_message(@topic)
      TestProducer.produce(message)
      assert_kafee_message(%{topic: @topic})
    end

    test "assert allows variable assignment" do
      message = BrodApi.generate_producer_message(@topic)
      TestProducer.produce(message)
      assert_kafee_message(%{topic: topic})
      assert topic == @topic
    end
  end

  describe "refute_kafee_message/2" do
    test "refutes an exact matching message" do
      message = BrodApi.generate_producer_message(@topic)
      @topic |> BrodApi.generate_producer_message() |> TestProducer.produce()
      assert_raise ExUnit.AssertionError, fn -> refute_kafee_message(^message) end
    end

    test "refutes a partial match" do
      @topic |> BrodApi.generate_producer_message() |> TestProducer.produce()
      assert_raise ExUnit.AssertionError, fn -> refute_kafee_message(%{topic: @topic}) end
    end
  end

  describe "kafee_messages/0" do
    test "returns a list of messages produced" do
      message = BrodApi.generate_producer_message(@topic)
      TestProducer.produce(message)
      assert [^message] = kafee_messages()
    end
  end
end
