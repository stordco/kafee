defmodule Kafee.KafkaCase do
  @moduledoc """
  A ExUnit that will setup a Kafka topic for you.

  ## Examples

      def MyTest do
        use Kafee.KafkaCase

        test "my test", %{brod_client_id: brod_client_id} do
          # ...
        end

        @tag topic: "my-test-topic"
        test "my test on a specific topic", %{brod_client_id: brod_client_id} do
          # ...
        end

        @tag partitions: 4
        test "my test with a specific partition count", %{brod_client_id: brod_client_id} do
          # ...
        end
      end

  """

  use ExUnit.CaseTemplate, async: false

  alias Kafee.{BrodApi, KafkaApi}

  using do
    quote do
      use Patch

      alias Kafee.{BrodApi, KafkaApi}
    end
  end

  setup context do
    {:ok, %{brod_client_id: Map.get(context, :brod_client_id, BrodApi.generate_client_id())}}
  end

  setup context do
    {:ok, %{topic: Map.get(context, :topic, KafkaApi.generate_topic())}}
  end

  setup context do
    {:ok, %{partitions: Map.get(context, :partitions, 1)}}
  end

  setup %{brod_client_id: brod_client_id, topic: topic, partitions: partitions} do
    :ok = KafkaApi.create_topic(topic, partitions)

    on_exit(fn ->
      KafkaApi.delete_topic(topic)
    end)

    BrodApi.client!(brod_client_id)

    :ok
  end

  setup do
    on_exit(fn ->
      Patch.restore(:brod)
      Patch.restore(:brod_client)
      Patch.restore(:brod_utils)
      Patch.restore(:brod_producer)
    end)

    :ok
  end
end
