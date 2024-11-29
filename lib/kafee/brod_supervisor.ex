defmodule Kafee.BrodSupervisor do
  @moduledoc """
  A supervisor for Brod-based producers and consumers that provides connection resiliency.
  This prevents Kafka connection issues from affecting your application's supervision tree
  and automatically retries connections when Kafka is unavailable.
  """
  use DynamicSupervisor
  require Logger

  @min_backoff 5_000
  @max_backoff 300_000

  def start_link(module, options) do
    name = supervisor_name(module)

    case DynamicSupervisor.start_link(__MODULE__, [], name: name) do
      {:ok, pid} ->
        {:ok, _retry_pid} = Kafee.BrodRetryManager.start_link(pid, module, options)
        {:ok, pid}

      error ->
        error
    end
  end

  @impl DynamicSupervisor
  def init([]) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 100_000,
      max_seconds: 1
    )
  end

  def start_child(supervisor, module, options) do
    adapter =
      case options[:adapter] do
        nil -> nil
        adapter when is_atom(adapter) -> adapter
        {adapter, _opts} -> adapter
      end

    backoff =
      min(
        @max_backoff,
        options[:restart_delay] || @min_backoff
      )

    brod_options =
      Keyword.merge(options,
        retry_backoff_ms: backoff,
        max_retries: 0
      )

    child_spec = %{
      id: module,
      start: {adapter, :start_brod_client, [module, brod_options]},
      restart: :permanent,
      shutdown: 5_000,
      restart_delay: backoff
    }

    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, _pid} = ok ->
        Logger.info("Started Kafka client for #{inspect(module)} using #{inspect(adapter)}")
        ok

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      error ->
        Logger.warning("Failed to start Kafka client for #{inspect(module)} using #{inspect(adapter)}")

        error
    end
  end

  defp supervisor_name(module) do
    # credo:disable-for-next-line
    :"#{module}.BrodSupervisor"
  end
end
