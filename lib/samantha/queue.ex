defmodule Samantha.Queue do
  @moduledoc """
  Handle sending / recv.ing gateway messages. The point of this module is that
  it can juggle all the send/recv queues instead of storing those in the shard
  or the gateway connection. This is important for this such as ex. waiting for
  both VOICE_STATE_UPDATE and VOICE_SERVER_UPDATE when connecting to voice.

  Queues are stored as a mapping of `identifier => queue`, where the identifier
  is generally something like a channel snowflake, the `gateway` queue, etc. 
  When performing queue operations, specifying the `identifier` is a 
  requirement. 

  This module is effectively just a somewhat higher-level wrapper over a couple
  Redis lists that we (ab)use as queues.
  """

  use GenServer

  require Logger
  alias Lace.Redis

  def start_link(state) do
    Logger.info "Starting link with queue with id #{inspect state[:id]}..."
    GenServer.start_link __MODULE__, state, name: __MODULE__
  end

  def init(state) do
    {:ok, state}
  end

  def handle_cast({:clear, id}, state) do
    Logger.info "[#{id}] Clearing queue #{state[:id]}:#{inspect id}"
    Redis.q ["DEL", "#{state[:id]}:#{inspect id}"]
    {:noreply, state}
  end

  def handle_cast({:push, id, val}, state) do
    val = unless is_binary(val) do
            val |> Poison.encode!
          else
            val
          end
    Logger.info "[#{id}] Pushing to #{state[:id]}:#{inspect id}: #{inspect val}"
    Redis.q ["RPUSH", "#{state[:id]}:#{inspect id}", val]
    {:noreply, state}
  end

  def handle_call({:pop, id}, _from, state) do
    {:ok, res} = Redis.q ["LPOP", "#{state[:id]}:#{inspect id}"]
    ##Logger.info "[#{id}] Popping from#{state[:id]}:#{inspect id}: #{inspect res}"
    case res do
      :undefined -> {:reply, nil, state}
      _ -> {:reply, res, state}
    end
  end

  def handle_call({:get_all, id}, _from, state) do
    {:ok, vals} = Redis.q ["LRANGE", "#{state[:id]}:#{inspect id}", 0, -1]
    #Logger.info "[#{id}] Getting all from #{state[:id]}:#{inspect id}: #{inspect vals, pretty: true}"
    case vals do
      :undefined -> {:reply, [], state}
      _ -> {:reply, vals, state}
    end
  end

  def handle_call({:length, id}, _from, state) do
    {:ok, len} = Redis.q ["LLEN", "#{state[:id]}:#{inspect id}"]
    Logger.info "[#{id}] Getting length of #{state[:id]}:#{inspect id}: #{inspect len}"
    {:reply, len, state}
  end
end
