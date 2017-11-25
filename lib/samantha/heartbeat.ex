defmodule Samantha.Heartbeat do
  use GenServer
  require Logger

  # API

  def start_link(parent_pid, seq_num) do
    GenServer.start_link __MODULE__, %{
      parent_pid: parent_pid,
      seq: seq_num,
    }
  end

  def update_seq(pid, num) do
    GenServer.cast pid, {:seq, num}
  end

  # Server

  def handle_info({:heartbeat, op, interval}, state) do
    import Samantha.Util
    unless is_nil interval do
      payload = binary_payload op, state[:seq]
      Logger.info "Sending heartbeat (interval: #{inspect interval}, seq: #{inspect state[:seq]})"
      Process.send_after self(), {:heartbeat, op, interval}, interval
      WebSockex.send_frame state[:parent_pid], {:binary, payload}
    else
      Logger.info "No heartbeat interval!?"
    end
    {:noreply, state}
  end

  def handle_cast({:seq, num}, state) do
    {:noreply, %{state | seq: num}}
  end

  def init(state) do
    {:ok, state}
  end
end