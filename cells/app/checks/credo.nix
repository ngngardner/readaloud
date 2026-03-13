{
  nixpkgs,
  self,
  beamPackages,
  mixFodDepsDev,
}:
nixpkgs.runCommand "credo-check"
  {
    nativeBuildInputs = [
      beamPackages.elixir
      beamPackages.erlang
      beamPackages.hex
      beamPackages.rebar3
      nixpkgs.gcc
      nixpkgs.gnumake
      nixpkgs.git
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

    cp --no-preserve=mode -R ${mixFodDepsDev} "$MIX_DEPS_PATH"
    mix deps.compile --no-deps-check
    mix run --no-deps-check --no-start -e 'Mix.Tasks.Credo.run(["--strict"])'
    touch $out
  ''
