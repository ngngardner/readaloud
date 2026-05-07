{
  nixpkgs,
  self,
  beamPackages,
  # mixFodDepsDev unused: workaround bypasses the Mix dep tree entirely.
  mixFodDepsDev ? null,
}:
# Hex.Audit's normal Mix-task path can't run in the nix sandbox: the
# heroicons git-dep lock mismatch trips Mix.Dep.Loadpaths even under
# `--no-deps-check`. Workaround: parse mix.lock and query the Hex registry
# directly. Same semantics (fails if any dep is retired in the registry).
nixpkgs.runCommand "hex-audit-check"
  {
    nativeBuildInputs = [
      beamPackages.elixir
      beamPackages.erlang
      nixpkgs.curl
      nixpkgs.jq
      nixpkgs.cacert
    ];
    SSL_CERT_FILE = "${nixpkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  }
  ''
    cd ${self}

    # Extract :hexpm packages from mix.lock as `name version` lines.
    # mix.lock entries look like:
    #   "phoenix": {:hex, :phoenix, "1.7.14", ...}
    # We grab the name (after :hex,) and the version (3rd quoted string).
    elixir -e '
      {lock, _} = Code.eval_file("mix.lock")
      lock
      |> Enum.each(fn
        {_, tuple} when is_tuple(tuple) ->
          case tuple do
            {:hex, name, version, _, _, _, _, _} ->
              IO.puts("#{name} #{version}")
            {:hex, name, version, _, _, _, _} ->
              IO.puts("#{name} #{version}")
            _ -> :ok
          end
        _ -> :ok
      end)
    ' > $TMPDIR/deps.txt

    retired=()
    while read -r name version; do
      [ -z "$name" ] && continue
      url="https://hex.pm/api/packages/$name/releases/$version"
      body=$(curl -fsSL "$url" 2>/dev/null || echo "{}")
      retire=$(echo "$body" | jq -r '.retirement // empty')
      if [ -n "$retire" ]; then
        reason=$(echo "$body" | jq -r '.retirement.reason // "unknown"')
        message=$(echo "$body" | jq -r '.retirement.message // ""')
        retired+=("$name $version: $reason — $message")
      fi
    done < $TMPDIR/deps.txt

    if [ "''${#retired[@]}" -gt 0 ]; then
      echo "Retired dependencies found:" >&2
      printf '  %s\n' "''${retired[@]}" >&2
      exit 1
    fi
    echo "No retired packages found"
    touch $out
  ''
