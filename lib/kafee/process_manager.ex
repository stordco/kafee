defmodule Kafee.ProcessManager do
  @moduledoc """
  Runs in a supervisor and manages restarting a process
  when is crashes. This is mainly used for the `:brod_client`
  process which will crash when it is unable to connect.

  ## What's different than the built in Supervisor?

  The main difference is allowing for a backoff time between
  restarts. This avoids crashing the whole application, though
  is not transparent and still needs to be handled in code.
  """

  use GenServer

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  @impl GenServer
  def init(opts) do
    supervisor = Map.fetch!(opts, :supervisor)
    child_spec = Map.drop(opts, [:supervisor])

    {:ok,
     %{
       child_pid: nil,
       child_spec: child_spec,
       monitor_ref: nil,
       supervisor: supervisor
     }, {:continue, :start_child}}
    |> IO.inspect(label: "result")
  end

  @doc false
  @impl GenServer
  def handle_continue(:start_child, %{supervisor: supervisor} = state) do
    IO.inspect(state, label: "state")
    IO.inspect(Process.whereis(supervisor), label: "supervisor response")

    if supervisor |> Process.whereis() |> is_nil() do
      Logger.debug("Waiting for supervisor to start")
      Process.sleep(100)
      handle_continue(:start_child, state)
    end

    Logger.debug("Starting child")

    with {:ok, state} <- start_child(state) do
      {:noreply, state}
    end
  end

  @doc false
  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, _reason}, %{monitor_ref: ref, child_pid: pid} = state) do
    Logger.info("Child down. Restarting")

    Process.sleep(:timer.seconds(10))

    with {:ok, state} <- start_child(state) do
      {:noreply, state}
    end
  end

  defp start_child(%{child_spec: child_spec, supervisor: supervisor} = state) do
    with {:ok, child_pid} <- Supervisor.start_child(supervisor, child_spec) |> IO.inspect(label: "supervisor start"),
         monitor_ref = Process.monitor(child_pid) do
      {:ok, %{state | child_pid: child_pid, monitor_ref: monitor_ref}}
    end
  end
end
