defmodule Kafee.MixProject do
  use Mix.Project

  def project do
    [
      app: :kafee,
      name: "Kafee",
      description: "Let's get energized with Kafka!",
      version: "3.5.4",
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      source_url: "https://github.com/stordco/kafee",
      dialyzer: [plt_add_apps: [:jason]],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.circle": :test
      ]
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
      {:broadway_kafka, "~> 0.3"},
      {:brod, "~> 3.17.0"},
      {:data_streams, ">= 1.2.0"},
      {:jason, ">= 1.0.0", optional: true},
      {:nimble_options, ">= 1.0.0"},
      {:opentelemetry_api, ">= 1.0.0"},
      {:protobuf, ">= 0.10.0", optional: true},
      {:telemetry, ">= 1.0.0"},

      # Dev & Test dependencies
      {:benchee, "~> 1.0", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.17.1", only: :test},
      {:ex_doc, "~> 0.30", only: [:dev, :test], runtime: false},
      {:faker, "~> 0.17", only: [:dev, :test]},
      {:opentelemetry, "~> 1.3", only: [:dev, :test]},
      {:opentelemetry_exporter, "~> 1.3", only: [:dev, :test]},
      {:patch, "~> 0.12.0", only: [:dev, :test]}
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
      before_closing_body_tag: &before_closing_body_tag/1,
      extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md"],
      groups_for_modules: [
        Consumer: [~r/Consumer/],
        Producer: [~r/Producer/],
        "Encoding & Decoding": [~r/EncoderDecoder/]
      ],
      main: "readme"
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script src="https://cdn.jsdelivr.net/npm/mermaid@8.13.3/dist/mermaid.min.js"></script>
    <script>
      document.addEventListener("DOMContentLoaded", function () {
        mermaid.initialize({ startOnLoad: false });
        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition, function (svgSource, bindListeners) {
            graphEl.innerHTML = svgSource;
            bindListeners && bindListeners(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""
end
