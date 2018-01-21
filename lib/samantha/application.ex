defmodule Samantha.Application do
  use Application

  require Logger

  def start(_type, _args) do
    Logger.info "Starting up!"
    # Get the shard count
    shard_count = unless is_nil System.get_env("SHARD_COUNT") do
      System.get_env("SHARD_COUNT") |> String.to_integer
    else
      (HTTPoison.get! "http://rancher-metadata/2015-12-19/self/service/scale").body |> String.to_integer
    end

    children = [
      Samantha.Queue,
      {Lace.Redis, %{
          redis_ip: System.get_env("REDIS_IP"), redis_port: 6379, pool_size: 100, redis_pass: System.get_env("REDIS_PASS")
        }},
      {Lace, %{name: System.get_env("NODE_NAME"), group: System.get_env("GROUP_NAME"), cookie: System.get_env("COOKIE")}},
      # Shard API, for gateway messages and shit
      Plug.Adapters.Cowboy.child_spec(:http, Samantha.Router, [], [
        dispatch: dispatch(),
        port: get_port(),
      ]),
      # Start the main shard process
      {Samantha.Shard, %{
          token: System.get_env("BOT_TOKEN"), 
          shard_count: shard_count
        }},
    ]

    opts = [strategy: :one_for_one, name: Samantha.Supervisor]
    # Start the "real" supervisor
    app_sup = Supervisor.start_link(children, opts)
    
    Logger.info "Shard count: #{inspect shard_count}"

    :timer.sleep 1000
    Samantha.Shard.try_connect()
    Logger.info "Shard booted!"

    app_sup
  end

  defp get_port do
    x = System.get_env "PORT"
    case x do
      nil -> 8937
      _ -> x |> String.to_integer
    end
  end

  defp dispatch do
    [
      {:_, [
        {:_, Plug.Adapters.Cowboy.Handler, {Samantha.Router, []}}
      ]},
    ]
  end
end
