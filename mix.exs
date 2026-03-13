defmodule Readaloud.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:deps_nix, "~> 0.4", only: :dev, runtime: false}
    ]
  end
end
