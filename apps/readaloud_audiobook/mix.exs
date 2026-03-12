defmodule ReadaloudAudiobook.MixProject do
  use Mix.Project

  def project do
    [
      app: :readaloud_audiobook,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ReadaloudAudiobook.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:readaloud_library, in_umbrella: true},
      {:readaloud_tts, in_umbrella: true},
      {:jason, "~> 1.4"},
      {:oban, "~> 2.19"},
      {:phoenix_pubsub, "~> 2.1"}
    ]
  end
end
