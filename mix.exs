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
      {:websockex, github: "queer/websockex"},
      {:lace, github: "queer/lace"},
      {:httpoison, "~> 0.13"},
      {:plug, "~> 1.4"},
      {:cowboy, "~> 1.1"},
      {:poison, "~> 3.1"},
      {:sentry, "~> 6.0.5"},
      {:hammer, "~> 2.1.0"},
      {:uuid, "~> 1.1"},
    ]
  end
end
