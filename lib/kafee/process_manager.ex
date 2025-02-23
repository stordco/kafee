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
       supervisor: supervisor,
       retry_count: 0,
       max_retries: get_max_retries()
     }, {:continue, :start_child}}
  end

  @doc false
  @impl GenServer
  def handle_continue(:start_child, state) do
    start_child(state)
  end

  defp start_child(%{child_spec: child_spec, supervisor: supervisor} = state) do
    case Supervisor.start_child(supervisor, child_spec) do
      {:ok, child_pid} when is_pid(child_pid) ->
        monitor_ref = Process.monitor(child_pid)
        {:noreply, %{state | child_pid: child_pid, monitor_ref: monitor_ref, retry_count: 0}}

      {:ok, :undefined} ->
        {:stop, :normal, state}

      {:error, {:already_started, child_pid}} when is_pid(child_pid) ->
        monitor_ref = Process.monitor(child_pid)
        {:noreply, %{state | child_pid: child_pid, monitor_ref: monitor_ref, retry_count: 0}}

      {:error, reason} ->
        restart_child(state, reason)
    end
  end

  @doc false
  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, reason}, %{monitor_ref: ref, child_pid: pid} = state) do
    restart_child(state, reason)
  end

  def handle_info(msg, state) when msg in [:start_child, :timeout] do
    start_child(state)
  end

  def handle_info(_req, state) do
    {:noreply, state}
  end

  defp restart_child(%{retry_count: retry_count, max_retries: max_retries} = state, reason) do
    restart_delay = get_restart_delay()
    Logger.info("Failed to start child or child process down. Restarting in #{restart_delay}ms...",
      reason: reason
    )

    if retry_count >= max_retries do
      Logger.error("Max retries reached (#{max_retries}). Shutting down ProcessManager.")
      {:stop, :normal, state}
    else
      {:noreply, %{state | retry_count: retry_count + 1}, restart_delay}
    end
  end

  defp get_restart_delay do
    Application.get_env(:kafee, :process_manager_restart_delay, :timer.seconds(10))
  end

  defp get_max_retries do
    Application.get_env(:kafee, :process_manager_max_retries, 5)
  end
end
