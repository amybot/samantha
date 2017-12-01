defmodule Samantha.Application do
  use Application

  require Logger

  def start(_type, _args) do
    import Supervisor.Spec
    children = [
      supervisor(Samantha.InternalSupervisor, [], name: Samantha.InternalSupervisor),
    ]

    opts = [strategy: :one_for_one, name: Samantha.Supervisor]
    {:ok, sup_pid} = Supervisor.start_link(children, opts)
    {:ok, shard_pid} = Samantha.InternalSupervisor.start_child worker(Samantha.Shard, [%{token: System.get_env("BOT_TOKEN"), shard_id: 0, shard_count: 1}], name: Samantha.Shard)

    :timer.sleep 1000
    Logger.info "!"
    GenServer.cast shard_pid, :gateway_connect
    Logger.warn "Should be connecting!"
    #
    #Logger.info "Done?"
    {:ok, sup_pid}
  end
end
