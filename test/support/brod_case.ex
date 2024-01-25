defmodule Kafee.BrodCase do
  @moduledoc """
  A ExUnit that will setup some `:brod` data for you. This is usually
  used with `Patch` to mock `:brod` calls.

  ## Examples

      def MyTest do
        use Kafee.BrodCase

        test "my test", %{brod_client_id: brod_client_id, topic: topic} do
          # ...
        end

        @tag topic: "my-test-topic"
        test "my test on a specific topic", %{brod_client_id: brod_client_id} do
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
