defmodule Samantha.Application do
  use Application

  require Logger

  def start(_type, _args) do
    import Supervisor.Spec
    children = [
      {Lace.Redis, %{redis_ip: System.get_env("REDIS_IP"), redis_port: 6379, pool_size: 10, redis_pass: System.get_env("REDIS_PASS")}},
      {Lace, %{name: "node_name", group: "group_name", cookie: "node_cookie"}},
      # Set up our dynamic supervisor
      {Samantha.InternalSupervisor, []},
    ]

    opts = [strategy: :one_for_one, name: Samantha.Supervisor]
    # Start the "real" supervisor
    app_sup = Supervisor.start_link(children, opts)
    Logger.info "Starting up!"
    # Get the shard count
    shard_count = (HTTPoison.get! "http://rancher-metadata/2015-12-19/self/service/scale").body |> String.to_integer
    Logger.info "Shard count: #{inspect shard_count}"
    # Start the shard worker under our dynamic supervisor
    {:ok, shard_pid} = Samantha.InternalSupervisor.start_child Samantha.Shard.child_spec(%{token: System.get_env("BOT_TOKEN"), shard_count: shard_count})
    :timer.sleep 1000
    send shard_pid, {:try_connect, 1}
    Logger.info "Shard booted!"
    #
    #Logger.info "Done?"
    app_sup
  end
end
