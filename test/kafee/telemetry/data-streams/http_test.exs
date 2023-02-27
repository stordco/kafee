defmodule Kafee.Telemetry.DataStreams.HttpTest do
  use ExUnit.Case

  alias Kafee.Telemetry.DataStreams.Http

  import Tesla.Mock

  setup do
    # mock(fn ->
    #  :ok
    # end)

    {:ok, [client: Http.new([])]}
  end

  test "can send data", %{client: client} do
    assert {:ok, %Tesla.Env{} = env} = Http.send_pipeline_stats(client, "asdfasdf")
  end
end
