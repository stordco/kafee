defmodule Kafee.ProcessManager do
  @moduledoc """
  Runs in a supervisor and manages restarting a process
  when it crashes. This is mainly used for the `:brod_client`
  process which will crash when it is unable to connect.

  ## What's different than the built in Supervisor?

  The main difference is allowing for a backoff time between
  restarts. This avoids crashing the whole application, though
  is not transparent and still needs to be handled in code.
  """

  use GenServer

  require Logger

  # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
  @log_prefix "#{inspect(__MODULE__)}]"
  @restart_delay Application.compile_env(:kafee, :process_manager_restart_delay, :timer.seconds(10))

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
  end

  @doc false
  @impl GenServer
  def handle_continue(:start_child, %{child_spec: child_spec, supervisor: supervisor} = state) do
    case Supervisor.start_child(supervisor, child_spec) do
      {:ok, child_pid} when is_pid(child_pid) ->
        monitor_ref = Process.monitor(child_pid)
        {:noreply, %{state | child_pid: child_pid, monitor_ref: monitor_ref}}

      {:ok, :undefined} ->
        {:stop, :normal, state}

      {:error, {:already_started, child_pid}} when is_pid(child_pid) ->
        monitor_ref = Process.monitor(child_pid)
        {:noreply, %{state | child_pid: child_pid, monitor_ref: monitor_ref}}

      {:error, reason} ->
        Logger.info("#{@log_prefix} Failed to start child. Restarting in #{@restart_delay}ms...",
          reason: reason
        )

        Process.sleep(@restart_delay)
        {:noreply, state, {:continue, :start_child}}
    end
  end

  @doc false
  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, reason}, %{monitor_ref: ref, child_pid: pid} = state) do
    Logger.info("#{@log_prefix} Child process down. Restarting in #{@restart_delay}ms...",
      reason: reason
    )

    Process.sleep(@restart_delay)
    {:noreply, state, {:continue, :start_child}}
  end

  def handle_info(_req, state) do
    {:noreply, state}
  end
end
