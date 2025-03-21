defmodule Kafee.ProcessManagerTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  require Logger

  alias Kafee.ProcessManager

  setup do
    {:ok, sup_pid} = Supervisor.start_link([], strategy: :one_for_one)
    %{supervisor: sup_pid}
  end

  describe "start_link/1" do
    test "starts the process manager with valid options", %{supervisor: sup_pid} do
      opts = %{
        supervisor: sup_pid,
        id: :test_child,
        start: {Agent, :start_link, [fn -> %{} end]}
      }

      assert {:ok, pid} = ProcessManager.start_link(opts)
      assert Process.alive?(pid)
    end

    test "fails to start without required supervisor option" do
      Process.flag(:trap_exit, true)

      opts = %{
        id: :test_child,
        start: {Agent, :start_link, [fn -> %{} end]}
      }

      assert {:error, {{:badkey, :supervisor}, _}} = ProcessManager.start_link(opts)
    end
  end

  describe "child process management" do
    test "successfully starts and monitors child process", %{supervisor: sup_pid} do
      log =
        capture_log(fn ->
          opts = %{
            supervisor: sup_pid,
            id: :test_child,
            start: {Agent, :start_link, [fn -> %{} end]}
          }

          {:ok, _pm_pid} = ProcessManager.start_link(opts)

          Process.sleep(100)

          [{_, child_pid, _, _}] = Supervisor.which_children(sup_pid)
          assert Process.alive?(child_pid)
        end)

      refute log =~ "Failed to start child"
    end

    test "restarts child process after crash", %{supervisor: sup_pid} do
      log =
        capture_log(fn ->
          opts = %{
            supervisor: sup_pid,
            id: :test_child,
            start: {Agent, :start_link, [fn -> %{} end]}
          }

          {:ok, _pm_pid} = ProcessManager.start_link(opts)
          Process.sleep(100)

          [{_, child_pid, _, _}] = Supervisor.which_children(sup_pid)
          Process.exit(child_pid, :kill)

          Process.sleep(100)

          [{_, new_child_pid, _, _}] = Supervisor.which_children(sup_pid)
          assert Process.alive?(new_child_pid)
          assert new_child_pid != child_pid
        end)

      assert log =~ "Failed to start child or child process dow"
      assert log =~ "Restarting in"
    end

    test "logs error when child fails to start", %{supervisor: sup_pid} do
      log =
        capture_log(fn ->
          opts = %{
            supervisor: sup_pid,
            id: :test_child,
            start: {NonExistentModule, :start_link, []}
          }

          {:ok, _pid} = ProcessManager.start_link(opts)
          Process.sleep(100)
        end)

      assert log =~ "Failed to start child"
    end

    test "shuts down after max retries", %{supervisor: sup_pid} do
      Process.flag(:trap_exit, true)

      original_delay = Application.get_env(:kafee, :process_manager_restart_delay)
      original_retries = Application.get_env(:kafee, :process_manager_max_retries)

      Application.put_env(:kafee, :process_manager_restart_delay, 10)
      Application.put_env(:kafee, :process_manager_max_retries, 2)

      log =
        capture_log(fn ->
          opts = %{
            supervisor: sup_pid,
            id: :test_child,
            start: {NonExistentModule, :start_link, []}
          }

          {:ok, pm_pid} = ProcessManager.start_link(opts)
          ref = Process.monitor(pm_pid)
          assert_receive {:DOWN, ^ref, :process, ^pm_pid, :normal}, 100
        end)

      if original_delay, do: Application.put_env(:kafee, :process_manager_restart_delay, original_delay)
      if original_retries, do: Application.put_env(:kafee, :process_manager_max_retries, original_retries)

      assert log =~ "Max retries reached"
      assert log =~ "Shutting down ProcessManager"
    end
  end
end
