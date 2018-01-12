defmodule Samantha.Discord do
  use WebSockex

  import Samantha.Util
  alias Lace.Redis

  require Logger

  @api_base "https://discordapp.com/api/v6"

  @large_threshold 250

  ##################
  ## Opcode stuff ##
  ##################

  @op_dispatch              0   # Recv.
  @op_heartbeat             1   # Send/Recv.
  @op_identify              2   # Send
  @op_status_update         3   # Send
  @op_voice_state_update    4   # Send
  @op_voice_server_ping     5   # Send
  @op_resume                6   # Send
  @op_reconnect             7   # Recv.
  @op_request_guild_members 8   # Send
  @op_invalid_session       9   # Recv.
  @op_hello                 10  # Recv.
  @op_heartbeat_ack         11  # Recv.

  # Lookup table for translation
  @opcodes %{
    @op_dispatch              => :dispatch,
    @op_heartbeat             => :heartbeat,
    @op_identify              => :identify,
    @op_status_update         => :status_update,
    @op_voice_state_update    => :voice_state_update,
    @op_voice_server_ping     => :voice_server_ping,
    @op_resume                => :resume,
    @op_reconnect             => :reconnect,
    @op_request_guild_members => :request_guild_members,
    @op_invalid_session       => :invalid_session,
    @op_hello                 => :hello,
    @op_heartbeat_ack         => :heartbeat_ack
  }

  ##############
  ## Internal ##
  ##############

  defp get(resource) do
    (HTTPoison.get! @api_base <> resource).body
    |> Poison.decode!
  end

  defp get_gateway_url do
    (get "/gateway")["url"] <> "/?v=6&encoding=etf"
  end

  ###############
  ## Websocket ##
  ###############

  def start_link(state) do
    # Check the initial state to make sure it's sane
    if state[:shard_id] >= state[:shard_count] do
      Logger.warn "Invalid shard count!?"
      Sentry.capture_message "Invalid shard count: id #{state[:shard_id]} >= #{state[:shard_count]}!"
    else
      Logger.info "Starting gateway connect!"
      gateway = get_gateway_url()
      Logger.info "Connecting to: #{gateway}"
      # Websocket PID is ready, connect to the gateway
      send state[:parent], {:shard_status, :gateway_connect}
      WebSockex.start(gateway, __MODULE__, state, [async: true])
    end
  end

  def init(state) do
    Logger.info "init?"
    {:once, state}
  end

  def handle_connect(conn, state) do
    Logger.info "Connected to gateway"
    unless is_nil state[:session_id] do
      Logger.info "We have a session; expect OP 10 -> OP 6."
    end
    headers = Enum.into conn.resp_headers, %{}
    ray = headers["Cf-Ray"]
    server = headers[:Server]
    Logger.info "Connected to #{server} ray #{ray}"
    new_state = state 
                |> Map.put(:client_pid, self())
                |> Map.put(:cf_ray, ray)
                |> Map.put(:trace, nil)
    # We connected to the gateway successfully, we're logging in now
    send state[:parent], {:shard_status, :logging_in}
    {:ok, new_state}
  end

  def handle_frame({:binary, msg}, state) do
    payload = :erlang.binary_to_term(msg)
    # When we get a gateway op, it'll be of the same form always, which makes our lives easier
    {res, reply, new_state} = handle_op payload[:op], payload, state
    case res do
      :reply -> {:reply, reply, new_state}
      :noreply -> {:ok, new_state}
      # Just immediately die
      :terminate -> {:close, new_state}
    end 
  end

  def handle_frame(msg, state) do
    Logger.info "Got msg: #{inspect msg}"
    {:ok, state}
  end

  def handle_disconnect(disconnect_map, state) do
    Logger.info "Disconnected from websocket!"
    Logger.debug "Disconnect info: #{inspect disconnect_map}"
    unless is_nil disconnect_map[:reason] do
      Logger.warn "Disconnect reason: #{inspect disconnect_map[:reason]}"
    end
    Logger.info "Killing heartbeat: #{inspect state[:heartbeat_pid]}"
    Process.exit(state[:heartbeat_pid], :kill)
    Logger.info "Killing gateway messenger: #{inspect state[:gateway_pid]}"
    Process.exit(state[:gateway_pid], :kill)
    Logger.info "Done! Please start a new gateway link."
    send state[:parent], {:shard_status, :disconnected}
    send state[:parent], :ws_exit
    # Disconnected from gateway, so not much else to say here
    {:ok, state}
  end

  def terminate(reason, _state) do
    Logger.info "Websocket terminating: #{inspect reason}"
    :ok
  end

  #########################
  ## Gateway op handling ##
  #########################

  # Handle specific ops
  def handle_op(@op_hello, payload, state) do
    Logger.info "Hello!!"

    d = payload[:d]
    # Spawn heartbeat worker and start heartbeat
    {:ok, heartbeat_pid} = Samantha.Heartbeat.start_link self(), state[:seq]
    send heartbeat_pid, {:heartbeat, @op_heartbeat, d[:heartbeat_interval]}
    heartbeat_state = state |> Map.put(:heartbeat_pid, heartbeat_pid)
    # Spawn gateway messenger
    {:ok, gateway_pid} = Samantha.Gateway.start_link self()
    heartbeat_state = heartbeat_state |> Map.put(:gateway_pid, gateway_pid)

    # Handle RESUME if we have a session already
    if is_nil state[:session_id] do
      # When we get HELLO, we need to start heartbeating immediately
      Logger.info "Hello: #{inspect d}"
      new_state = heartbeat_state
                  |> Map.put(:trace, d[:trace])
                  |> Map.put(:interval, d[:heartbeat_interval])
                  |> Map.put(:seq, nil)
      Logger.info "Welcome to Discord!"
      # Got HELLO, IDENTIFY ourselves
      send state[:parent], {:shard_status, :identifying}
      {:reply, identify(new_state), new_state}
    else
      # We have a session ID, so we should RESUME over it
      Logger.info "Resuming session..."

      send state[:parent], {:shard_status, :resuming}
      {:reply, resume(heartbeat_state), heartbeat_state}
    end
  end

  def handle_op(@op_reconnect, _payload, state) do
    # When we get a :reconnect, we need to do a FULL reconnect
    Logger.info "Got :reconnect, killing WS to start over."
    {:terminate, nil, state}
  end

  def handle_op(@op_dispatch, payload, state) do
    #Logger.info "Got :dispatch t: #{inspect payload[:t]}"
    {:ok, new_state} = handle_event(payload[:t], payload[:d], state)
    # Update heartbeat monitor
    Samantha.Heartbeat.update_seq state[:heartbeat_pid], payload[:s]
    send state[:parent], {:seq, payload[:s]}
    {:noreply, nil, new_state}
  end

  def handle_op(@op_invalid_session, payload, state) do
    Logger.info "Got :invalid_session!"
    can_resume = payload[:d]
    if can_resume do
      # We're able to resume, wait a bit then send a RESUME
      Logger.info "Can resume, wait a little bit..."
      :timer.sleep 2500
      {:reply, resume(state), state}
    else
      # We're not able to resume, drop the session and start over
      Logger.info "Can't resume, backing off 6s..."
      :timer.sleep 6000
      {:reply, identify(state), state}
    end
  end

  # Generic op handling
  def handle_op(opcode, payload, state) do
    Logger.debug "Got unhandled op: #{inspect opcode} (#{inspect @opcodes[opcode]})" 
          <> " with payload: #{inspect payload}"
    {:noreply, nil, state}
  end

  ############################
  ## Gateway event handling ##
  ############################

  def handle_event(:READY, data, state) do
    Logger.info "Ready: Gateway protocol: #{inspect data[:v]}"
    Logger.info "Ready: We are: #{inspect data[:user]}"
    Logger.info "Ready: _trace: #{inspect data[:_trace]}"
    Logger.info "Ready: We are in #{inspect length(data[:guilds])} guilds."
    # Once we get :READY, we need to cache the unavailable guilds so 
    # that we know whether to fire :GUILD_CREATE or :GUILD_JOIN correctly. 
    Logger.debug "Ready: Initial guilds: #{inspect data[:guilds]}"
    guilds = data[:guilds]
             |> Enum.map(fn(x) -> x[:id] end)
             |> Enum.to_list
    Logger.debug "READY with guilds: #{inspect guilds}"
    new_state = state
                |> Map.put(:session_id, data[:session_id])
                |> Map.put(:trace, data[:_trace])
                |> Map.put(:user, data[:user])
                |> Map.put(:initial_guilds, guilds)
    Logger.info "All traces: #{inspect new_state[:trace]}"
    # Start polling for gateway messages
    Logger.info "Starting gateway poll task..."
    send state[:gateway_pid], :poll_gateway
    # Pass our session to the parent
    send state[:parent], {:session, data[:session_id]}
    # We connected and got the :READY, so we're all the way in :tada:
    send state[:parent], {:shard_status, :ready}
    Logger.info "Fully up!"
    {:ok, new_state}
  end

  def handle_event(:RESUMED, data, state) do
    Logger.info "Resumed with #{inspect data}"
    # Our RESUME worked, so we're good
    send state[:parent], {:shard_status, :ready}
    {:ok, %{state | trace: data[:_trace]}}
  end

  def handle_event(event, data, state) do
    Logger.debug "Got unhandled event: #{inspect event} with payload #{inspect data}"
    # If this is a GUILD_CREATE event, check if we need to queue an OP8 
    # REQUEST_GUILD_MEMBERS
    if event == :GUILD_CREATE do
      if data[:member_count] > @large_threshold do
        Logger.info "Requesting guild members for large guild #{data[:id]}"
        payload = payload_base @op_request_guild_members, %{"guild_id" => data[:id], "query" => "", "limit" => 0}, nil, nil
        GenServer.cast Samantha.Queue, {:push, "gateway", payload}
      end
    end
    try do
      Redis.q ["RPUSH", System.get_env("EVENT_QUEUE"), Poison.encode!(%{"t" => Atom.to_string(event), "d" => data})]
    rescue 
      e -> Sentry.capture_exception e, [stacktrace: System.stacktrace()]
    end
    {:ok, state}
  end

  ###########
  ## Other ##
  ###########

  defp identify(state) do
    Logger.info "Identifying as [#{inspect state[:shard_id]}, #{inspect state[:shard_count]}]..."
    data = %{
      "token" => state[:token],
      "properties" => %{
        "$os" => "BEAM",
        "$browser" => "samantha",
        "$device" => "samantha"
      },
      "compress" => false,
      "large_threshold" => @large_threshold,
      "shard" => [state[:shard_id], state[:shard_count]],
    }
    payload = binary_payload @op_identify, data
    Logger.info "Done!"
    {:binary, payload}
  end

  defp resume(state) do
    seq = GenServer.call state[:parent], :seq
    Logger.info "Resuming from seq #{inspect seq}"
    payload = binary_payload @op_resume, %{
      "session_id" => state[:session_id],
      "token" => state[:token],
      "seq" => seq,
      "properties" => %{
        "$os" => "BEAM",
        "$browser" => "samantha",
        "$device" => "samantha"
      },
      "compress" => false,
      "shard" => [state[:shard_id], state[:shard_count]],
    }
    {:binary, payload}
  end
end