defmodule Samantha.Shard do
  use GenServer
  require Logger
  alias Lace.Redis

  def start_link(opts) do
    GenServer.start_link __MODULE__, opts, name: __MODULE__
  end

  def init(opts) do
    state = %{
      ws_pid: nil,
      seq: nil,
      session_id: nil,
      token: opts[:token],
      shard_id: nil,
      shard_count: opts[:shard_count],
      shard_status: :unknown,
    }

    Process.send_after self(), {:try_connect, 1}, 1000

    {:ok, state}
  end

  def handle_call(:get_self, _from, state) do
    {:ok, self} = Redis.q ["HGET", "shard-users", state[:shard_id]]
    {:reply, self, state}
  end

  def handle_call(:seq, _from, state) do
    {:reply, state[:seq], state}
  end

  def handle_call(:shard_count, _from, state) do
    {:reply, state[:shard_count], state}
  end

  def handle_call(:shard_id, _from, state) do
    {:reply, state[:shard_id], state}
  end

  def handle_info({:try_connect, tries}, state) do
    if state[:shard_count] == 1 do
      send self(), {:gateway_connect, 0}
      {:noreply, state}
    else
      if tries == 1 do
        Logger.info "[SHARD] Sharding with #{System.get_env("CONNECTOR_URL") <> "/shard"}"
      end
      Logger.debug "[SHARD] Connecting (attempt #{inspect tries}) with shard count #{inspect state[:shard_count]}..."
      # Try to get a valid "token" from the shard connector
      shard_payload = %{
        "bot_name"    => System.get_env("BOT_NAME"),
        "shard_count" => state[:shard_count],
      }
      {:ok, payload} = Poison.encode shard_payload
      Logger.debug "[SHARD] Payload (#{payload})"
      response = HTTPoison.post!(System.get_env("CONNECTOR_URL") <> "/shard", payload, [{"Content-Type", "application/json"}])
      Logger.debug "[SHARD] Got response: #{inspect response.body}"
      shard_res = response.body |> Poison.decode!
      case shard_res["can_connect"] do
        true -> 
          send self(), {:gateway_connect, shard_res["shard_id"]}
          {:noreply, state}
        false -> 
          # Can't connect, try again in 1s
          Logger.debug "[SHARD] Unable to connect, backing off and retrying..."
          Process.send_after self(), {:try_connect, tries + 1}, 1000
          {:noreply, state}
      end
    end
  end

  def handle_info({:seq, num}, state) do
    Logger.debug "[SHARD] New sequence number: #{inspect num}"
    Redis.q ["HSET", "shard-seq", state[:shard_id], num]
    {:noreply, %{state | seq: num}}
  end

  def handle_info({:session, session_id}, state) do
    Logger.info "[SHARD] Parent got a new session."
    Redis.q ["HSET", "shard-sessions", state[:shard_id], session_id]
    {:noreply, %{state | session_id: session_id}}
  end

  def handle_info({:shard_heartbeat, shard_id}, state) do
    # TODO: Move this to the discord gateway process so that the id can be reassigned on cascading failures etc.
    if is_nil System.get_env "SHARD_COUNT" do
      shard_payload = %{
        "bot_name" => System.get_env("BOT_NAME"),
        "shard_id" => shard_id,
      }
      try do
        HTTPoison.post! System.get_env("CONNECTOR_URL") <> "/heartbeat", (shard_payload |> Poison.encode!), [{"Content-Type", "application/json"}], [recv_timeout: 500]
      rescue
        e -> 
          Logger.warn "[SHARD] Error with heartbeat! #{inspect e}"
          Sentry.capture_message "Heartbeat failed: #{inspect e}", [stacktrace: System.stacktrace()]
      end
      # Heartbeat every ~second
      Process.send_after self(), {:shard_heartbeat, shard_id}, 1000
    end
    {:noreply, state}
  end

  def handle_info({:gateway_connect, shard_id}, state) do
    # TODO: Ensure valid shard_id
    # Check if we're already connected
    if is_nil state[:ws_pid] do
      Logger.info "[SHARD] Starting a gateway connection..."
      # Not connected, so start the ws connection

      # Pull session id if possible
      {:ok, session_id} = Redis.q ["HGET", "shard-sessions", shard_id]
      {:ok, seq} = Redis.q ["HGET", "shard-seq", shard_id]
      state = unless is_nil(session_id) or (session_id == :undefined) do
                unless is_nil(seq) or (seq == :undefined) do
                  Logger.info "[SHARD] Restoring old session..."
                  seq = String.to_integer seq
                  %{state | session_id: session_id, seq: seq}
                else
                  Logger.warn "[SHARD] Invalid sequence number '#{inspect seq}'"
                  state
                end
              else
                Logger.warn "[SHARD] Invalid session '#{inspect session_id}'"
                state
              end

      # Give the gateway connection the initial state to work from
      shard_id = unless is_integer shard_id do
        shard_id |> String.to_integer
      else
        shard_id
      end
      initial_state = %{
        token: state[:token],
        parent: self(),
        session_id: state[:session_id],
        shard_id: shard_id,
        shard_count: state[:shard_count],
      }

      {res, pid} = Samantha.Discord.start_link initial_state
      if res == :ok do
        ref = Process.monitor pid
        Logger.info "[SHARD] Started WS: pid #{inspect pid}, ref #{inspect ref}"
        # Start heartbeating
        send self(), {:shard_heartbeat, shard_id}
        {:noreply, %{state | ws_pid: pid, shard_id: shard_id, shard_status: :ws_open}}
      else
        {:noreply, state}
      end
    else
      Logger.warn "[SHARD] Got :gateway_connect when already connected, ignoring..."
      {:noreply, state}
    end
  end

  def handle_info({:shard_status, status}, state) do
    {:noreply, %{state | shard_status: status}}
  end

  def handle_info(:ws_exit, state) do
    unless is_nil state[:ws_pid] do
      Process.exit state[:ws_pid], :kill
    else
      Logger.info "[SHARD] WS died, let's restart it with shard #{inspect state[:shard_id]}"
      Process.send_after self(), {:gateway_connect, state[:shard_id]}, 2500
    end
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    Logger.debug "[SHARD] Got :DOWN: "
    Logger.debug "[SHARD] pid #{inspect pid}. ref #{inspect ref}"
    Logger.debug "[SHARD] reason: #{inspect reason}"
    cond do
      pid == state[:ws_pid] ->
        Logger.info "[SHARD] WS died, let's restart it with shard #{inspect state[:shard_id]}"
        Process.send_after self(), {:gateway_connect, state[:shard_id]}, 2500
        {:noreply, %{state | ws_pid: nil}}
      true ->
        {:noreply, state}
    end
  end
end