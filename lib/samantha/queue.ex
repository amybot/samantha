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

  This module is effectively just a somewhat higher-level wrapper over Erlang's
  :queue module.
  """

  use GenServer

  require Logger

  def start_link(_) do
    GenServer.start_link __MODULE__, [], name: __MODULE__
  end

  def init([]) do
    state = %{
      # Have the initial "global" gateway queue to start
      "gateway" => :queue.new(),
    }

    {:ok, state}
  end

  def handle_cast({:clear, id}, state) do
    Map.put state, id, :queue.new()
    {:noreply, state}
  end

  def handle_cast({:push, id, val}, state) do
    queue = if Map.has_key?(state, id) do
        state[id]
      else
        :queue.new()
      end
    # Push at the tail of the queue
    state = Map.put state, id, :queue.in(val, queue)
    {:noreply, state}
  end

  def handle_call({:pop, id}, _from, state) do
    queue = state[id]
    unless is_nil queue do
      # Pop from the head of the queue
      {val, new_queue} = case :queue.out queue do
        {{:value, val}, new_queue} -> {val, new_queue}
        {:empty, new_queue} -> {nil, new_queue}
      end
      {:reply, val, %{state | id => new_queue}}
    else
      {:reply, nil, state}
    end
  end

  def handle_call({:get_all, id}, _from, state) do
    if Map.has_key?(state, id) do
      queue = state[id]
      list = :queue.to_list queue
      {:reply, list, state}
    else
      {:reply, [], state}
    end
  end

  def handle_call({:length, id}, _from, state) do
    queue = state[id]
    unless is_nil queue do
      {:reply, :queue.len(queue), state}
    else
      {:reply, -1, state}
    end
  end
end
