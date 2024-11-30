defmodule Kafee.BrodThrottleManager do
  @moduledoc """
  Manages throttling of Kafka client restarts to prevent aggressive reconnection attempts.

  The throttle manager accepts either a fixed delay (integer) or a function that takes
  the number of restarts and returns a delay value in milliseconds.

  ## Throttling Behavior

  When a Kafka client disconnects or fails:
  1. The client process terminates
  2. A backoff period begins (default: 5000ms)
  3. During the backoff period, all restart attempts are rejected
  4. When backoff completes, one restart attempt is allowed
  5. If that attempt fails, a new backoff period begins

  ## Configuration

  The restart delay can be configured in three ways:

  1. Fixed delay (integer in milliseconds):
      ```
      restart_delay: 10_000  # 10 second delay between restarts
      ```

  2. Dynamic delay (function that takes retry count):
      ```
      restart_delay: fn retries -> retries * 5_000 end  # Linear backoff
      ```

  3. Default delay (when no option specified):
      ```
      @default_backoff 5_000  # 5 second fixed delay
      ```

  ## Example Logs

  The throttle manager emits logs to track its behavior:
  ```
  [info] Kafka client for MyApp.MyConsumer went down, scheduling retry
  [debug] Setting restart backoff to 5000ms
  [debug] Restart backoff of 5000ms completed
  [info] Allowing restart for MyApp.MyConsumer
  [info] Successfully connected to Kafka for MyApp.MyConsumer
  ```
  """

  use GenServer
  require Logger

  @default_backoff 5_000

  def start_link(module, backoff \\ @default_backoff) do
    GenServer.start_link(__MODULE__, {0, nil, backoff}, name: name(module))
  end

  def can_restart?(module) do
    restartable? =
      module
      |> name()
      |> GenServer.call(:can_restart?)

    case restartable? do
      true ->
        Logger.info("Allowing restart for #{inspect(module)}")
        true

      false ->
        Logger.info("Throttling restart for #{inspect(module)}")
        false
    end
  end

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:can_restart?, _from, {restarts, timer, backoff}) do
    if timer do
      {:reply, false, {restarts, timer, backoff}}
    else
      delay = calculate_backoff(backoff, restarts)
      Logger.debug("Setting restart backoff to #{delay}ms")
      new_timer = Process.send_after(self(), {:allow_restart, delay}, delay)
      {:reply, true, {restarts + 1, new_timer, backoff}}
    end
  end

  @impl GenServer
  def handle_info({:allow_restart, delay}, {restarts, _timer, backoff}) do
    Logger.debug("Restart backoff of #{delay}ms completed")
    {:noreply, {restarts, nil, backoff}}
  end

  defp calculate_backoff(backoff, _restarts) when is_integer(backoff), do: backoff
  defp calculate_backoff(backoff_fn, restarts) when is_function(backoff_fn, 1), do: backoff_fn.(restarts)
  defp calculate_backoff(_, _), do: @default_backoff

  defp name(module) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    :"#{inspect(module)}.BrodThrottleManager"
  end
end
