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

      ProcessManager.start_link(opts)
      assert_receive {:EXIT, _pid, {{:badkey, :supervisor}, _stack}}
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

      assert log =~ "Child process down"
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
  end
end
