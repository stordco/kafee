defmodule Kafee.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :kafee,
      version: @version,
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Kafee.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:elsa, "~> 1.0.0-rc.3"},

      # Dev & Test dependencies
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end
end
