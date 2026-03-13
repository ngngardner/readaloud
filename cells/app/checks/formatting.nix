{
  nixpkgs,
  self,
  l,
  treefmtData,
  beamPackages,
  mixFodDepsDev,
}:
let
  treefmtConfig = (nixpkgs.formats.toml { }).generate "treefmt.toml" treefmtData;
in
nixpkgs.runCommand "formatting-check"
  {
    nativeBuildInputs = [
      nixpkgs.treefmt
      nixpkgs.nixfmt
      nixpkgs.biome
      nixpkgs.git
      beamPackages.elixir
      beamPackages.erlang
      beamPackages.hex
      beamPackages.rebar3
      nixpkgs.gcc
      nixpkgs.gnumake
      nixpkgs.pkg-config
      nixpkgs.sqlite
    ];
    ELIXIR_ERL_OPTIONS = "+fnu";
    MIX_REBAR3 = "${beamPackages.rebar3}/bin/rebar3";
  }
  ''
    cp -r ${self} source && chmod -R +w source && cd source
    export HOME=$TMPDIR
    export HEX_HOME="$TMPDIR/.hex"
    export MIX_HOME="$TMPDIR/.mix"
    export MIX_ENV=dev
    export MIX_DEPS_PATH="$TMPDIR/deps"
    export REBAR_GLOBAL_CONFIG_DIR="$TMPDIR/rebar3"
    export REBAR_CACHE_DIR="$TMPDIR/rebar3.cache"

    # Link hex from ERL_LIBS into _build so mix can find it
    mkdir -p _build/$MIX_ENV/lib
    while IFS=: read -r -d ':' lib; do
      for dir in "$lib"/*; do
        [ -d "$dir" ] || continue
        dest=$(basename "$dir" | cut -d '-' -f1)
        ln -sf "$dir" "_build/$MIX_ENV/lib/$dest"
      done
    done <<< "$ERL_LIBS:"

    # Copy dev deps — fetchMixDeps provides source directories for all deps
    cp --no-preserve=mode -R ${mixFodDepsDev} "$MIX_DEPS_PATH"

    # Compile deps without checking lock status.
    # This bypasses the heroicons git dep lock mismatch (fetchMixDeps strips
    # .git metadata, but --no-deps-check skips the lock verification).
    mix deps.compile --no-deps-check

    # Check Elixir formatting via mix run.
    # mix format has no --no-deps-check flag, but mix run does —
    # invoking Format.run through mix run bypasses dep lock checking.
    mix run --no-deps-check --no-start \
      -e 'Mix.Tasks.Format.run(["--check-formatted"])'

    # Check nix and JS formatting with treefmt (Elixir handled above)
    cp ${treefmtConfig} treefmt.toml
    treefmt --no-cache --fail-on-change
    touch $out
  ''
