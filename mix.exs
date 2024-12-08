defmodule SonosElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :sonos_elixir,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:sweet_xml, "~> 0.7"},
      {:elixir_xml_to_map, "~> 3.1"},
      {:xml_builder, "~> 2.3.0"},
      {:timex, "~> 3.7"},
      {:httpoison, "~> 2.2.0"},
      {:exsync, "~>0.4.1", env: :dev}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
