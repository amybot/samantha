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
      shard_id: nil,
      shard_count: opts[:shard_count],
    }
    {:ok, state}
  end

  def handle_call(:seq, _from, state) do
    {:reply, state[:seq], state}
  end

  def handle_info({:try_connect, tries}, state) do
    Logger.info "Connecting (attempt #{inspect tries}) with shard count #{inspect state[:shard_count]}..."
    # Try to get a valid "token" from the shard connector
    shard_payload = %{
      "bot_name"    => System.get_env("BOT_NAME"),
      "shard_count" => state[:shard_count],
    }
    Logger.info "Sharding with #{System.get_env("CONNECTOR_URL") <> "/shard"}"
    {:ok, payload} = Poison.encode shard_payload
    Logger.info "Payload (#{payload})"
    response = HTTPoison.post!(System.get_env("CONNECTOR_URL") <> "/shard", payload, [{"Content-Type", "application/json"}])
    Logger.info "Got response: #{inspect response.body}"
    shard_res = response.body |> Poison.decode!
    case shard_res["can_connect"] do
      true -> 
        send self(), {:gateway_connect, shard_res["shard_id"]}
        {:noreply, state}
      false -> 
        # Can't connect, try again in 1s
        Logger.info "Unable to connect, backing off and retrying..."
        Process.send_after self(), {:try_connect, tries + 1}, 1000
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

  def handle_info(:shard_heartbeat, state) do
    shard_payload = %{
      "bot_name"    => System.get_env("BOT_NAME"),
      "shard_id" => state[:shard_id],
    }
    HTTPoison.post! System.get_env("CONNECTOR_URL") <> "/heartbeat", (shard_payload |> Poison.encode!), [{"Content-Type", "application/json"}]
    # Heartbeat every ~second
    Process.send_after self(), :shard_heartbeat, 1000
    {:noreply, state}
  end

  def handle_info({:gateway_connect, shard_id}, state) do
    # Check if we're already connected
    if is_nil state[:ws_pid] do
      Logger.info "Starting a gateway connection..."
      # Not connected, so start the ws connection and otherwise do the needful

      # Give the gateway connection the initial state to work from
      initial_state = %{
        token: state[:token],
        parent: self(),
        session_id: state[:session_id],
        shard_id: shard_id,
        shard_count: state[:shard_count],
      }

      {:ok, pid} = Samantha.Discord.start_link initial_state
      ref = Process.monitor pid
      Logger.info "Started WS: pid #{inspect pid}, ref #{inspect ref}"
      # Start heartbeating
      Process.send_after self(), :shard_heartbeat, 2000
      {:noreply, %{state | ws_pid: pid, shard_id: shard_id}}
    else
      Logger.warn "Got :gateway_connect when already connected, ignoring..."
      {:noreply, state}
    end
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
      Process.send_after self(), {:gateway_connect, state[:shard_id]}, 2500
    end
    {:noreply, %{state | ws_pid: nil}}
  end
end