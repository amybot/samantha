# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure your application as:
#
#     config :samantha, key: :value
#
# and access this configuration in your application as:
#
#     Application.get_env(:samantha, :key)
#
# You can also configure a 3rd-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env}.exs"
config :logger, level: :info

config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  included_environments: ["prod"],
  environment_name: System.get_env("ENV_NAME") || "dev"
#  enable_source_code_context: true,
#  root_source_code_path: File.cwd!

# Shard gateway message-sending doesn't need to be ratelimited across shards, 
# so the ETS backend should be perfectly fine. 
config :hammer,
  backend: {Hammer.Backend.ETS,
            [expiry_ms: 60_000 * 60 * 4,
             cleanup_interval_ms: 60_000 * 10]}

# rancher clustering
config :libcluster,
  topologies: [
    shard: [
      strategy: Cluster.Strategy.Rancher,
      config: [
        node_basename: "samantha"
      ]
    ],
    gateway: [
      strategy: Cluster.Strategy.Rancher,
      config: [
        node_basename: "gateway"
      ]
    ]
  ]
