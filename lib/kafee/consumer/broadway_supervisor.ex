defmodule Kafee.Consumer.BroadwaySupervisor do
  @moduledoc """
  Supervisor for the BroadwayAdapter.

  Mainly to allow for the Task.Supervisor to exist in this supervision tree, because
  that will be used to supervise async operations during batches, if configuration is set to do so.

  As far as users of the library, this is implementation detail.

  """
  use Supervisor
  alias Kafee.Consumer.BroadwayAdapter

  def start_link(consumer, options) do
    Supervisor.start_link(__MODULE__, {consumer, options}, name: __MODULE__)
  end

  @impl Supervisor
  def init({consumer, options}) do
    children = [
      {BroadwayAdapter, [consumer, options]},
      {Task.Supervisor, name: BroadwayAdapter.TaskSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
