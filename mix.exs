defmodule Kafee.MixProject do
  use Mix.Project

  def project do
    [
      app: :kafee,
      name: "Kafee",
      description: "Let's get energized with Kafka!",
      version: "1.0.3",
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      source_url: "https://github.com/stordco/kafee"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:brod, "~> 3.16.2"},

      # Dev & Test dependencies
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.19.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.27", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp package do
    [
      files: ~w(lib mix.exs .formatter.exs README.md CHANGELOG.md),
      licenses: ["UNLICENSED"],
      links: %{
        Changelog: "https://github.com/stordco/kafee/releases",
        GitHub: "https://github.com/stordco/kafee"
      },
      organization: "stord"
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md"]
    ]
  end
end
