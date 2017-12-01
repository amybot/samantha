defmodule Samantha.Shard do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link __MODULE__, opts #, name: __MODULE__
  end

  def init(opts) do
    state = %{
      ws_pid: nil,
      seq: nil,
      session_id: nil,
      token: opts[:token],
      shard_id: opts[:shard_id],
      shard_count: opts[:shard_count],
    }
    Logger.info "Started shard."
    {:ok, state}
  end

  def handle_call(:seq, _from, state) do
    {:reply, state[:seq], state}
  end

  def handle_cast(:gateway_connect, state) do
    # Check if we're already connected
    if is_nil state[:ws_pid] do
      Logger.info "Starting a gateway connection..."
      # Not connected, so start the ws connection and otherwise do the needful

      # Give the gateway connection the initial state to work from
      initial_state = %{
        token: state[:token],
        parent: self(),
        session_id: state[:session_id],
        shard_id: state[:shard_id],
        shard_count: state[:shard_count],
      }

      {:ok, pid} = Samantha.Discord.start_link initial_state
      ref = Process.monitor pid
      Logger.info "Started WS: pid #{inspect pid}, ref #{inspect ref}"
      {:noreply, %{state | ws_pid: pid}}
    else
      Logger.warn "Got :gateway_connect when already connected, ignoring..."
      {:noreply, state}
    end
  end

  def handle_info({:seq, num}, state) do
    Logger.debug "New sequence number: #{inspect num}"
    {:noreply, %{state | seq: num}}
  end

  def handle_info({:session, session_id}, state) do
    Logger.info "Got a new session."
    {:noreply, %{state | session_id: session_id}}
  end

  def handle_info(:gateway_connect, state) do
    GenServer.cast self(), :gateway_connect
    {:noreply, state}
  end

  def handle_info(:ws_exit, state) do
    Process.exit state[:ws_pid], :kill
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    Logger.debug "Got :DOWN: "
    Logger.debug "pid #{inspect pid}. ref #{inspect ref}"
    Logger.debug "reason: #{inspect reason}"
    if pid == state[:ws_pid] do
      Logger.info "WS died, let's restart it."
      Process.send_after self(), :gateway_connect, 2500
    end
    {:noreply, %{state | ws_pid: nil}}
  end
end