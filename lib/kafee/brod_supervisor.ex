defmodule Kafee.BrodSupervisor do
  use DynamicSupervisor
  require Logger

  def start_link(module, options) do
    name = supervisor_name(module)

    case DynamicSupervisor.start_link(__MODULE__, [], name: name) do
      {:ok, pid} ->
        backoff = options[:restart_delay] || 1_000
        {:ok, _state_pid} = Kafee.BrodThrottleManager.start_link(module, backoff)
        {:ok, _retry_pid} = Kafee.BrodRetryManager.start_link(pid, module, options)
        {:ok, pid}

      error ->
        error
    end
  end

  @impl DynamicSupervisor
  def init([]) do
    Process.flag(:trap_exit, true)

    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 100_000,
      max_seconds: 1
    )
  end

  def start_child(supervisor, module, options) do
    case Kafee.BrodThrottleManager.can_restart?(module) do
      true ->
        do_start_child(supervisor, module, options)

      false ->
        {:error, :throttled}
    end
  end

  defp do_start_child(supervisor, module, options) do
    adapter =
      case options[:adapter] do
        nil -> nil
        adapter when is_atom(adapter) -> adapter
        {adapter, _opts} -> adapter
      end

    child_spec = %{
      id: module,
      start: {adapter, :start_brod_client, [module, options]},
      restart: :temporary,
      shutdown: 5_000
    }

    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, pid} = ok ->
        Process.monitor(pid)
        Logger.info("Started Kafka client for #{inspect(module)} using #{inspect(adapter)}")
        ok

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      error ->
        Logger.warning("Failed to start Kafka client for #{inspect(module)} using #{inspect(adapter)}")
        error
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  defp supervisor_name(module) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    :"#{module}.BrodSupervisor"
  end
end
