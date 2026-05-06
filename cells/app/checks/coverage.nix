# ExUnit coverage check. Runs the umbrella test suite under
# `mix test --cover --export-coverage default`, then aggregates with
# `mix test.coverage` and fails if total line coverage is below
# `threshold` (default 80).
#
# This is the CI-parity gate. The agent inner-loop equivalent is
# `mix test.cover` (umbrella alias) which prints the same numbers
# without failing.
{
  nixpkgs,
  self,
  beamPackages,
  mixFodDeps,
  threshold ? 80,
}:
nixpkgs.runCommand "coverage-check"
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
    inherit threshold;
  }
  ''
    cp -r ${self} source && chmod -R +w source && cd source
    export HOME=$TMPDIR
    export HEX_HOME="$TMPDIR/.hex"
    export MIX_HOME="$TMPDIR/.mix"
    export MIX_ENV=test
    export MIX_DEPS_PATH="$TMPDIR/deps"
    export REBAR_GLOBAL_CONFIG_DIR="$TMPDIR/rebar3"
    export REBAR_CACHE_DIR="$TMPDIR/rebar3.cache"

    # Link hex packages from ERL_LIBS into _build so mix resolves them
    # without a network fetch (mirrors the credo check).
    mkdir -p _build/$MIX_ENV/lib
    while IFS=: read -r -d ':' lib; do
      for dir in "$lib"/*; do
        [ -d "$dir" ] || continue
        dest=$(basename "$dir" | cut -d '-' -f1)
        ln -sf "$dir" "_build/$MIX_ENV/lib/$dest"
      done
    done <<< "$ERL_LIBS:"

    cp --no-preserve=mode -R ${mixFodDeps} "$MIX_DEPS_PATH"
    mix deps.compile --no-deps-check

    # Fresh sandbox → fresh SQLite. Migrate before tests. Run via
    # `mix run --no-deps-check` so the heroicons git lock mismatch
    # in the sandbox doesn't stop us (same trick as the credo check).
    mix run --no-deps-check --no-start -e 'Mix.Tasks.Ecto.Create.run([])'
    mix run --no-deps-check --no-start -e 'Mix.Tasks.Ecto.Migrate.run([])'

    # Run the suite with coverage export. `--export-coverage default`
    # writes per-app `.coverdata` files; `mix test.coverage` from the
    # umbrella root aggregates them and prints the combined total.
    mix test --no-deps-check --cover --export-coverage default

    # Aggregate. `mix test.coverage` has a hardcoded 90% threshold that
    # ignores project config and exits non-zero below it — we tolerate
    # the failure exit and apply our own threshold below. Invoked via
    # `mix run --no-deps-check` to bypass the heroicons sandbox check.
    mix run --no-deps-check --no-start \
      -e 'Mix.Tasks.Test.Coverage.run([])' 2>&1 | tee coverage.out || true

    total=$(awk -F'[ %]' '/^[[:space:]]*[0-9.]+%[[:space:]]*\| Total/ {gsub(/^ +/,""); print $1; exit}' coverage.out)
    if [ -z "$total" ]; then
      echo "ERROR: could not parse coverage total from mix test.coverage output"
      exit 1
    fi

    echo "Total line coverage: $total% (threshold: $threshold%)"

    # bash arithmetic doesn't do floats; multiply by 100 and compare ints.
    total_x100=$(printf '%.0f' "$(echo "$total * 100" | ${nixpkgs.bc}/bin/bc)")
    threshold_x100=$((threshold * 100))

    if [ "$total_x100" -lt "$threshold_x100" ]; then
      echo "FAIL: coverage $total% is below threshold $threshold%"
      exit 1
    fi

    echo "PASS: coverage $total% meets threshold $threshold%"
    touch $out
  ''
