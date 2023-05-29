defmodule Smppex.Mixfile do
  use Mix.Project

  def project do
    [
      app: :smppex,
      version: "3.0.6",
      elixir: "~> 1.11",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      source_url: "https://github.com/savonarola/smppex",
      deps: deps(),
      description: description(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      package: package(),
      dialyzer: [
        plt_add_apps: [:ssl]
      ],
      docs: docs()
    ]
  end

  def application do
    [applications: [:logger, :ranch]]
  end

  defp deps do
    [
      {:excoveralls, "~> 0.5", only: :test},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:earmark, "~> 1.4", only: :dev},
      {:ex_doc, "~> 0.23", only: :dev},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ranch, "~> 2.0"}
    ]
  end

  defp description do
    "SMPP 3.4 protocol and framework implemented in Elixir"
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      name: :smppex,
      files: ["lib", "mix.exs", "*.md", "LICENSE"],
      maintainers: ["Ilya Averyanov"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/savonarola/smppex"
      }
    ]
  end

  defp docs do
    [
      main: "examples",
      extras: [
        "EXAMPLES.md",
        "PROJECTS.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
