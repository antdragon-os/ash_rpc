defmodule Ashrpc.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/antdragon-os/ash_rpc"

  def project do
    [
      app: :ash_rpc,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "⚠️ EXPERIMENTAL: Expose Ash Resource actions over tRPC with Plug-compatible router/controller and tooling. Breaking changes may occur frequently.",
      package: package(),
      source_url: @source_url,
      docs: docs(),
      aliases: [
        precommit: [
          "format",
          "compile --warnings-as-errors",
          "credo --strict",
          "docs"
        ],
        "hex.publish": [
          "hex.publish --yes"
        ],
        "hex.publish.dry_run": [
          "hex.publish --dry-run"
        ],
        "release.local": [
          "precommit",
          "hex.publish.dry_run"
        ],
        "release.check": [
          "deps.get",
          "compile",
          "cmd MIX_ENV=test mix test",
          "docs"
        ]
      ],
      elixirc_options: [warnings_as_errors: false]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ash, "~> 3.0"},
      {:spark, "~> 2.0"},
      {:splode, "~> 0.2"},
      {:plug, "~> 1.15"},
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, ">= 2.1.0", optional: true},
      {:phoenix, ">= 1.7.0", optional: true},
      {:ash_phoenix, ">= 1.0.0", optional: true},
      {:sourceror, "~> 1.0"},
      {:igniter, "~> 0.6", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:decimal, "~> 2.0"},
      {:telemetry, "~> 1.0"}
    ]
  end

  defp package do
    [
      name: "ash_rpc",
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE guides .formatter.exs),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "HexDocs" => "https://hexdocs.pm/ash_rpc"
      },
      maintainers: ["Rosaan Ramasamy"],
      source_url: @source_url
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      authors: ["Rosaan Ramasamy"],
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/quickstart.md",
        "guides/router.md",
        "guides/generator.md",
        "guides/frontend.md",
        "guides/authentication.md"
      ]
    ]
  end
end
