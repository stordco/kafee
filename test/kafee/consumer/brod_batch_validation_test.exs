defmodule Kafee.Consumer.BrodBatchValidationTest do
  use ExUnit.Case

  defmodule ConsumerWithoutHandleBatch do
    use Kafee.Consumer

    @impl Kafee.Consumer
    def handle_message(_message) do
      :ok
    end
  end

  test "raises ArgumentError when consumer doesn't implement handle_batch in batch mode" do
    assert_raise ArgumentError, ~r/must implement handle_batch\/1 when using batch mode/, fn ->
      Kafee.Consumer.BrodBatchWorker.init(
        %{group_id: "test", partition: 0, topic: "test"},
        %{
          consumer: ConsumerWithoutHandleBatch,
          options: [],
          adapter_options: []
        }
      )
    end
  end
end