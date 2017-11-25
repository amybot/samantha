defmodule Samantha.Mixfile do
  use Mix.Project

  def project do
    [
      app: :samantha,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Samantha.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:websockex, github: "queer/websockex"}, #"~> 0.4.0"},
      {:httpoison, "~> 0.13"},
      {:poison, "~> 3.1"},
      #{:redix, ">= 0.0.0"},
    ]
  end
end
