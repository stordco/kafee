defmodule Kafee.BrodRetryManager do
  use GenServer
  require Logger

  @min_backoff 5_000

  def start_link(supervisor, module, options) do
    GenServer.start_link(__MODULE__, {supervisor, module, options}, name: manager_name(module))
  end

  @impl GenServer
  def init(state = {supervisor, module, options}) do
    case Kafee.BrodSupervisor.start_child(supervisor, module, options) do
      {:ok, _pid} ->
        {:ok, state}

      _error ->
        Logger.warning("Initial Kafka connection failed for #{inspect(module)}, will retry in background")
        schedule_retry()
        {:ok, state}
    end
  end

  @impl GenServer
  def handle_info(:retry, state = {supervisor, module, options}) do
    case Kafee.BrodSupervisor.start_child(supervisor, module, options) do
      {:ok, _pid} ->
        Logger.info("Successfully connected to Kafka for #{inspect(module)}")
        {:noreply, state}

      _error ->
        schedule_retry()
        {:noreply, state}
    end
  end

  # Handle process exits
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state = {_supervisor, module, _options}) do
    Logger.info("Kafka client for #{inspect(module)} went down, scheduling retry")
    schedule_retry()
    {:noreply, state}
  end

  defp schedule_retry do
    Process.send_after(self(), :retry, @min_backoff)
  end

  defp manager_name(module) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    :"#{module}.BrodRetryManager"
  end
end
