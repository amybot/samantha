defmodule Samantha.Gateway do
  use WebSockex

  import Samantha.Util

  require Logger

  @api_base "https://discordapp.com/api/v6"

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
    gateway = get_gateway_url()
    Logger.info "Connecting to: #{gateway}"
    WebSockex.start(gateway, __MODULE__, state)
  end

  def init(state) do
    new_state = state
                |> Map.put(:client_pid, self())
    Logger.info "state: #{inspect new_state}"
    {:once, new_state}
  end

  def handle_connect(conn, state) do
    Logger.info "Connected to gateway"
    {:ok, state}
  end

  def handle_frame({:binary, msg}, state) do
    payload = :erlang.binary_to_term(msg)
    # When we get a gateway op, it'll be of the same form always, which makes our lives easier
    {res, reply, new_state} = handle_op payload[:op], payload, state
    case res do
      :reply -> {:reply, reply, new_state}
      :noreply -> {:ok, new_state}
    end 
  end

  def handle_frame(msg, state) do
    Logger.info "Got msg: #{inspect msg}"
    {:ok, state}
  end

  def handle_disconnect(disconnect_map, state) do
    Logger.info "Got disconnect: #{inspect disconnect_map}"
    {:ok, state}
  end

  ################
  # External API #
  ################

  def handle_info({:heartbeat, interval}, state) do
    unless is_nil interval do
      payload = binary_payload @op_heartbeat, state[:seq]
      Logger.info "Sending heartbeat (interval: #{inspect interval}, seq: #{inspect state[:seq]})"
      Process.send_after self(), {:heartbeat, interval}, interval
      {:reply, {:binary, payload}, state}
    else
      Logger.warn "No interval!?"
      {:ok, state}
    end
  end

  #########################
  ## Gateway op handling ##
  #########################

  # Handle specific ops
  def handle_op(@op_hello, payload, state) do
    Logger.info "Hello!!"

    # Handle RESUME if we have a session already
    if is_nil state[:session_id] do
      # When we get HELLO, we need to start heartbeating immediately
      d = payload[:d]
      Logger.info "Hello: #{inspect d}"
      new_state = state
                  |> Map.put(:trace, d[:trace])
                  |> Map.put(:interval, d[:heartbeat_interval])
                  |> Map.put(:seq, nil)

      send self(), {:heartbeat, d[:heartbeat_interval]}
      Logger.info "Welcome to Discord!"
      {:reply, identify(new_state), new_state}
    else
      # We have a session ID, so we should RESUME over it
      Logger.info "Resuming session..."

      {:reply, resume(state), state}
    end
  end

  def handle_op(@op_reconnect, _payload, state) do
    # When we get a :reconnect, we need to do a FULL reconnect
    #       {:reconnect, new_conn, new_module_state} ->
    Logger.info "Got :reconnect!"
    {:reconnect, state}
  end

  def handle_op(@op_dispatch, payload, state) do
    Logger.info "Got :dispatch t: #{inspect payload[:t]}"
    {:ok, new_state} = handle_event(payload[:t], payload[:d], state)
    {:noreply, nil, %{new_state | seq: payload[:s]}}
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
      Logger.info "Can't resume, backing off 5s..."
      :timer.sleep 5000
      {:reply, identify(state), state}
    end
  end

  # Generic op handling
  def handle_op(opcode, payload, state) do
    Logger.warn "Got unhandled op: #{inspect opcode} (#{inspect @opcodes[opcode]})" 
          <> "with payload: #{inspect payload}"
    {:noreply, nil, state}
  end

  ############################
  ## Gateway event handling ##
  ############################

  def handle_event(:READY, data, state) do
    Logger.info "Ready: Gateway protocol: #{inspect data[:v]}"
    Logger.info "Ready: We are: #{inspect data[:user]}"
    Logger.info "Ready: _trace: #{inspect data[:_trace]}"
    new_state = state
                |> Map.put(:session_id, data[:session_id])
                |> Map.put(:trace, MapSet.to_list(MapSet.union(
                    MapSet.new([state[:trace]]),
                    MapSet.new([data[:_trace]])
                  )))
    Logger.info "All traces: #{inspect new_state[:trace]}"
    {:ok, new_state}
  end

  def handle_event(_event, _data, state) do
    # Logger.warn "Got unhandled event: #{inspect event} with payload #{inspect data}"
    {:ok, state}
  end

  ###########
  ## Other ##
  ###########

  defp identify(state) do
    Logger.info "Identifying..."
    data = %{
      "token" => state[:token],
      "properties" => %{
        "$os" => "BEAM",
        "$browser" => "samantha",
        "$device" => "samantha"
      },
      "compress" => false,
      "large_threshold" => 250,
      # TODO: shard
    }
    payload = binary_payload @op_identify, data
    Logger.info "Done!"
    {:binary, payload}
  end

  defp resume(state) do
    Logger.info "Resuming..."
    payload = binary_payload @op_resume, %{
      token: state[:token],
      session_id: state[:session_id],
      seq: state[:seq]
    }
    Logger.info "Done!"
    {:binary, payload}
  end
end