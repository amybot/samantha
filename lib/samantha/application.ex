defmodule Samantha.Application do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec
    children = [
      worker(Samantha.Gateway, [%{token: System.get_env("BOT_TOKEN")}], name: :gateway)
    ]

    opts = [strategy: :one_for_one, name: Samantha.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
