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
      # Using PartitionSupervisor to protect against Task.Supervisor being the bottleneck.
      # See: https://hexdocs.pm/elixir/1.15.6/Task.Supervisor.html#module-scalability-and-partitioning
      {PartitionSupervisor, child_spec: Task.Supervisor, name: BroadwayAdapter.TaskSupervisors}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
