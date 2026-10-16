defmodule Noizu.Notion.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/noizu-labs/noizu_notion"

  def project do
    [
      app: :noizu_notion,
      version: @version,
      elixir: "~> 1.20",
      name: "Noizu.Notion",
      description: "Elixir client for the Notion API (Notion-Version 2026-03-11).",
      package: package(),
      source_url: @source_url,
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE", "docs/API-CONTRACT.md"]
    ]
  end

  defp package do
    [
      name: "noizu_notion",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Notion API docs" => "https://developers.notion.com/reference/intro"
      },
      files: ~w(lib docs .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp deps do
    [
      {:req, "~> 0.7"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16", only: :test},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end
end
