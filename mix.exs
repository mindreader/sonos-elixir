defmodule SonosElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :sonos_elixir,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixir_paths: elixir_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Sonos.Supervisor, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixir_paths(:test), do: ["lib", "test/support"]
  defp elixir_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.7.14"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:gettext, "~> 0.20"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:sweet_xml, "~> 0.7"},
      {:elixir_xml_to_map, "~> 3.1"},
      {:xml_builder, "~> 2.3.0"},
      {:timex, "~> 3.7"},
      {:httpoison, "~> 2.2.0"},
      # {:exsync, "~>0.4.1", only: :dev},
      {:big_brother_ex, "~> 0.1", only: :dev},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      # "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      # "ecto.reset": ["ecto.drop", "ecto.setup"],
      # test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind sonos_elixir", "esbuild sonos_elixir"],
      "assets.deploy": [
        "tailwind sonos_elixir --minify",
        "esbuild sonos_elixir --minify",
        "phx.digest"
      ]
    ]
  end
end
