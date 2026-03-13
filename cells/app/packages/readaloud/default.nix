{
  inputs,
  cell,
}:
let
  inherit (inputs) nixpkgs;
  beamPackages = nixpkgs.beam.packagesWith nixpkgs.beam.interpreters.erlang_27;

  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "readaloud-deps";
    version = "0.1.0";
    src = inputs.self;
    hash = "sha256-Gm3SnOma94LqRyfGnCqg1bs15yzbNCisp2836aiI2Fo=";
  };
in
beamPackages.mixRelease {
  pname = "readaloud";
  version = "0.1.0";
  src = inputs.self;

  inherit mixFodDeps;

  nativeBuildInputs = with nixpkgs; [
    nodejs_22
    esbuild
    tailwindcss_4
  ];

  # Override esbuild/tailwind download steps — use nixpkgs binaries
  ESBUILD_PATH = nixpkgs.lib.getExe nixpkgs.esbuild;
  TAILWIND_PATH = nixpkgs.lib.getExe nixpkgs.tailwindcss_4;

  # elixir_make/exqlite needs a writable HOME for cache dirs;
  # must be set before configurePhase which runs mix deps.compile
  postUnpack = ''
    export HOME="$TEMPDIR"
  '';

  preBuild = ''
    # Ensure esbuild and tailwind use nixpkgs binaries, not downloaded ones
    export MIX_ESBUILD_PATH="${nixpkgs.lib.getExe nixpkgs.esbuild}"
    export MIX_TAILWIND_PATH="${nixpkgs.lib.getExe nixpkgs.tailwindcss_4}"
  '';

  postBuild = ''
    # Run esbuild and tailwind directly — bypasses Mix dep checks
    # that fail on the heroicons git dep (lock mismatch in sandbox).
    # The config/config.exs defines these same args for the Mix wrappers.

    echo "Building CSS with tailwindcss..."
    tailwindcss \
      --input=apps/readaloud_web/assets/css/app.css \
      --output=apps/readaloud_web/priv/static/assets/css/app.css \
      --minify

    echo "Building JS with esbuild..."
    # NODE_PATH must include deps and _build for phoenix/phoenix_live_view
    # resolution (mirrors the env config in config/config.exs)
    NODE_PATH="deps:_build/$MIX_BUILD_PREFIX" \
    esbuild \
      apps/readaloud_web/assets/js/app.js \
      --bundle --target=es2022 \
      --outdir=apps/readaloud_web/priv/static/assets/js \
      "--external:/fonts/*" "--external:/images/*" \
      "--alias:@=apps/readaloud_web/assets" \
      --minify

    echo "Running Phoenix digest..."
    # Provide dummy SECRET_KEY_BASE for config/runtime.exs evaluation.
    # Run phx.digest from web app context via mix run to bypass dep checks.
    cd apps/readaloud_web
    SECRET_KEY_BASE="build-time-placeholder-not-used-at-runtime-0000000000000000" \
    mix run --no-deps-check --no-start \
      -e 'Mix.Tasks.Phx.Digest.run([])'
    cd "$NIX_BUILD_TOP/source"
  '';

  # Runtime dependencies
  buildInputs = with nixpkgs; [
    openssl
    ncurses
    calibre
    poppler-utils
  ];

  # Release name matches the release defined in mix.exs
  mixReleaseName = "readaloud";

  meta = {
    description = "ReadAloud — audiobook generation and reading companion";
    mainProgram = "readaloud";
  };
}
