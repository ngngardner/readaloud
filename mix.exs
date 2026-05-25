defmodule Readaloud.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      # The umbrella `mix test.cover` is for visibility — the canonical
      # gate is `cells/app/checks/coverage.nix` (currently 80%). Setting
      # the Mix-level threshold to 0 keeps the local alias informational.
      test_coverage: [threshold: 0],
      releases: [
        readaloud: [
          applications: [
            readaloud_library: :permanent,
            readaloud_reader: :permanent,
            readaloud_tts: :permanent,
            readaloud_importer: :permanent,
            readaloud_audiobook: :permanent,
            readaloud_web: :permanent
          ]
        ]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.cover": :test,
        "test.reset": :test,
        precommit: :test
      ]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  # Dialyzer needs :mix in the PLT to recognize Mix.Task callbacks used by
  # custom mix tasks (e.g. apps/readaloud_audiobook/lib/mix/tasks/retranscribe.ex).
  # :ex_unit is required in MIX_ENV=test (precommit env) so the PLT can
  # resolve ExUnit.CaseTemplate / Callbacks references in test/support/*.
  # `app_tree` builds a per-deps PLT instead of one giant blob — faster
  # incremental rebuilds when a single dep changes.
  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_add_deps: :app_tree,
      flags: [:error_handling, :underspecs]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:deps_nix, "~> 0.4", only: :dev, runtime: false}
    ]
  end

  # Umbrella-level aliases. The test entry points are documented in
  # CLAUDE.md — keep those docs and these aliases in sync.
  defp aliases do
    [
      "test.e2e": [
        "cmd nix build .#checks.x86_64-linux.e2e -L --print-build-logs"
      ],
      "test.cover": ["test --cover --export-coverage default"],
      "test.reset": [
        "ecto.drop --quiet",
        "ecto.create --quiet",
        "ecto.migrate --quiet"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "dialyzer",
        "test"
      ]
    ]
  end
end
