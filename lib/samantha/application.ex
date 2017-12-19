defmodule Samantha.Application do
  use Application

  require Logger

  def start(_type, _args) do
    import Supervisor.Spec
    children = [
      {Lace.Redis, %{redis_ip: "127.0.0.1", redis_port: 6379, pool_size: 10, redis_pass: "a"}},
      {Lace, %{name: "node_name", group: "group_name", cookie: "node_cookie"}},
      # Set up our dynamic supervisor
      {Samantha.InternalSupervisor, [], name: Samantha.InternalSupervisor},
    ]

    opts = [strategy: :one_for_one, name: Samantha.Supervisor]
    # Start the "real" supervisor
    app_sup = Supervisor.start_link(children, opts)
    :timer.sleep 1000
    Logger.info "Starting up!"
    # Get the shard count
    shard_count = (HTTPoison.get! "http://rancher-metadata/2015-12-19/self/service/scale").body |> String.to_integer
    # Start the shard worker under our dynamic supervisor
    {:ok, shard_pid} = Samantha.InternalSupervisor.start_child worker(Samantha.Shard, [%{token: System.get_env("BOT_TOKEN"), shard_count: shard_count}], name: Samantha.Shard)
    Logger.info "Shard booted!"
    #
    #Logger.info "Done?"
    app_sup
  end
end
