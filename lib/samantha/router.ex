defmodule Samantha.Router do
  use Plug.Router
  require Logger
  import Samantha.Util

  @op_voice_state_update 4

  plug :match
  plug :dispatch

  get "/", do: send_resp(conn, 200, "yes")

  get "/self" do
    self = GenServer.call Samantha.Shard, :get_self
    res = self |> Poison.encode!
    conn |> send_resp(200, res)
  end

  get "/shard/count" do
    data = %{
      "shard_count" => GenServer.call(Samantha.Shard, :shard_count)
    }
    res = data |> Poison.encode!
    conn |> send_resp(200, res)
  end

  get "/voice", do: send_resp(conn, 200, "voice!")

  get "/voice/:guild/:channel/connect" do
    res = try_get_voice(guild, channel) |> Poison.encode!
    conn |> send_resp(200, res)
  end

  get "/voice/:guild/disconnect" do
    payload = payload_base @op_voice_state_update, %{
                "guild_id" => guild, 
                "channel_id" => nil, 
                "self_mute" => false, 
                "self_deaf" => true,
              }, nil, nil
    GenServer.cast Samantha.Queue, {:push, "gateway", payload}

    res = %{"disconnect_queued" => true} |> Poison.encode!
    conn |> send_resp(200, res)
  end

  #match _, do: send_resp(conn, 404, "no")

  defp try_get_voice(guild_id, channel_id) do
    payload = payload_base @op_voice_state_update, %{
                "guild_id" => String.to_integer(guild_id),
                "channel_id" => String.to_integer(channel_id),
                "self_mute" => false, 
                "self_deaf" => true,
              }, nil, nil
    GenServer.cast Samantha.Queue, {:push, "gateway", payload}
    {voice_state_update, voice_server_update} = get_voice_events String.to_integer(guild_id), 
                                                  String.to_integer(channel_id)
    voice_state_update = Poison.decode!(voice_state_update)
    voice_server_update = Poison.decode!(voice_server_update)

    # Construct the data that we can send directly to hotspring
    # Have to do some "preprocessing" of the voice server event
    voice_server_final = %{
      "token" => voice_server_update["token"],
      "guild_id" => voice_server_update["guild_id"] |> Integer.to_string,
      "endpoint" => voice_server_update["endpoint"],
    }
    %{
      "bot_id" => Integer.to_string(voice_state_update["user_id"]),
      # We add this in discord.ex, handle_event(:VOICE_STATE_UPDATE, data, state)
      # This is not part of "vanilla" gateway events
      "shard_id" => voice_state_update["shard_id"],
      "session" => voice_state_update["session_id"],
      "vsu" => voice_server_final,
    }
  end

  defp get_voice_events(guild_id, channel_id) do
    # This is totally the wrong thing to do :^)
    # Block until we have both events
    Process.sleep 50
    cq = "cvsu:#{inspect channel_id}"
    gq = "gvsu:#{inspect guild_id}"
    # Check if we've gotten both events...
    cev = GenServer.call Samantha.Queue, {:get_all, cq}
    gev = GenServer.call Samantha.Queue, {:get_all, gq}
    if length(cev) > 0 and length(gev) > 0 do
      # ...take them, and clear the queues...
      GenServer.cast Samantha.Queue, {:clear, cq}
      GenServer.cast Samantha.Queue, {:clear, gq}
      # ...then send them to the caller
      {hd(cev), hd(gev)}
    else
      # Otherwise, try again
      get_voice_events guild_id, channel_id
    end
  end
end