defmodule SonosElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :sonos_elixir,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Sonos, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.0"},
      {:httpoison, "~> 1.0"},
      {:sweet_xml, "~> 0.6"},
      {:xml_builder, "~> 2.0.0"},
      {:flex_logger, "~> 0.2.0"},
      {:timex, "~> 3.0"},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
