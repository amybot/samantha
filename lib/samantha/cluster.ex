defmodule Samantha.Cluster do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link __MODULE__, opts, name: __MODULE__
  end

  def init(opts) do
    Process.send_after self(), :gateway_connect, 250
    {:ok, opts}
  end

  def handle_info(:gateway_connect, state) do
    Process.send_after Samantha.Cluster, :try_shard, 1000
    {:noreply, state}
  end

  def handle_info(:try_shard, state) do
    gateway = :syn.find_by_key :gateway
    send gateway, {:start_sharding, self()}
    {:noreply, state}
  end

  def handle_info({:assign_shard, shard}, state) do
    Logger.info "Got shard assigned: #{inspect shard}"
    Process.sleep 1000
    gateway = :syn.find_by_key :gateway
    send gateway, {:finish_sharding, self()}
    {:ok, state}
  end
end