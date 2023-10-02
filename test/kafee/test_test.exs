defmodule Kafee.TestTest do
  use ExUnit.Case, async: true
  use Kafee.Test

  defmodule TestProducer do
    use Kafee.Producer, producer_backend: Kafee.Producer.TestBackend
  end

  def create_message(opts \\ %{}) do
    Map.merge(
      %Kafee.Producer.Message{
        topic: Faker.Pokemon.name(),
        key: Faker.Team.creature(),
        value: Faker.Markdown.markdown(),
        partition: 0,
        partition_fun: :random,
        headers: []
      },
      opts
    )
  end

  setup do
    start_supervised!({TestProducer, []})
    :ok
  end

  describe "assert_kafee_message/2" do
    test "asserts an exact matching message" do
      message = create_message()
      TestProducer.produce(message)
      assert_kafee_message(^message)
    end

    test "asserts a partial match" do
      message = create_message(%{key: "testing key"})
      TestProducer.produce(message)
      assert_kafee_message(%{key: "testing key"})
    end

    test "asserts allow matching" do
      message = create_message()
      %{key: key} = message
      TestProducer.produce(message)
      assert_kafee_message(%{key: ^key})
    end

    test "assert allows variable assignment" do
      message = create_message()
      TestProducer.produce(message)
      assert_kafee_message(%{key: key})
      assert key
    end
  end

  describe "refute_kafee_message/2" do
    test "refutes an exact matching message" do
      message = create_message()
      TestProducer.produce(create_message())
      refute_kafee_message(^message)
    end

    test "refutes a partial match" do
      TestProducer.produce(create_message(%{key: "refute test"}))
      refute_kafee_message(%{key: "refute test", topic: "refute topic"})
    end
  end

  describe "kafee_messages/0" do
    test "returns a list of messages produced" do
      message = create_message()
      TestProducer.produce(message)
      assert [^message] = kafee_messages()
    end
  end
end
