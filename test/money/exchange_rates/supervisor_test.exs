defmodule Money.ExchangeRates.SupervisorTest do
  use ExUnit.Case, async: false

  alias Money.ExchangeRates.Supervisor

  setup do
    start_supervised!(Money.ExchangeRates.Supervisor)
    :ok
  end

  describe "start_retriever/1" do
    setup do
      Supervisor.stop_retriever()
      Supervisor.delete_retriever()
    end

    test "returns {:ok, pid} and transitions to :running" do
      assert {:ok, pid} = Supervisor.start_retriever()
      assert is_pid(pid)
      assert Supervisor.retriever_running?()
    end

    test "returns {:error, {:already_started, pid}} when retriever is already running" do
      {:ok, _pid} = Supervisor.start_retriever()
      assert {:error, {:already_started, pid}} = Supervisor.start_retriever()
      assert is_pid(pid)
    end
  end

  describe "stop_retriever/0" do
    test "returns :ok" do
      assert Supervisor.stop_retriever() == :ok
    end

    test "transitions status to :stopped" do
      Supervisor.stop_retriever()

      refute Supervisor.retriever_running?()
    end
  end

  describe "restart_retriever/0" do
    setup do
      Supervisor.stop_retriever()
    end

    test "returns {:ok, pid}" do
      assert {:ok, pid} = Supervisor.restart_retriever()
      assert is_pid(pid)
    end

    test "transitions status back to :running" do
      Supervisor.restart_retriever()

      assert Supervisor.retriever_running?()
    end
  end

  describe "delete_retriever/0" do
    setup do
      Supervisor.stop_retriever()
    end

    test "returns :ok" do
      assert Supervisor.delete_retriever() == :ok
    end

    test "transitions status to :not_started" do
      Supervisor.delete_retriever()

      assert Supervisor.retriever_status() == :not_started
    end
  end
end
