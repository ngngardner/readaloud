# Idiomatic std/hive Refactor — Design Spec

**Date:** 2026-03-13
**Status:** Approved (rev3)
**Predecessor:** `/home/noah/projects/readaloud/docs/superpowers/specs/2026-03-12-nix-infrastructure-overhaul-design.md`

## Overview

Refactor the readaloud flake from a hybrid std/manual pattern to idiomatic divnix/std and divnix/hive usage. Move all outputs into cell blocks. Drop treefmt-nix. Use `(functions "nixosModules")` + `std.pick` to harvest system-independent NixOS modules.

## Motivation

The initial infrastructure overhaul (2026-03-12) used std for devshells/packages but manually defined checks, formatter, and nixosModules in the flake.nix growOn extras. This refactor aligns with std's intended usage by:

- Using `(nixago "configs")` block type instead of inline nixago configs in devshells.nix
- Using `(anything "checks")` block type instead of manual `runCommand` definitions in flake.nix
- Using `(functions "nixosModules")` + `std.pick` instead of manual import for NixOS module export
- Dropping `treefmt-nix` input — treefmt config is defined once in the nixago block

**Reference pattern:** `/home/noah/projects/configs/flake.nix` — uses `hive.growOn`, `hive.blockTypes`, `hive.collect`, `nixago "configs"` block, `std.harvest`.

## Inputs

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  hive = {
    url = "github:divnix/hive";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  std.follows = "hive/std";
};
```

**Removed:** `treefmt-nix` (replaced by nixago treefmt config), `devshell` and `nixago` explicit inputs.

**Changed:** `std` now follows through `hive` (matching configs pattern). Hive's flake.nix wires its own `devshell` and `nixago` inputs into std before exposing it, so `std.follows = "hive/std"` includes all integrations (devshell, nixago) automatically. No separate follows needed.

## Cell Blocks

```nix
cellBlocks =
  with std.blockTypes;
  [
    (devshells "devshells")
    (installables "packages")
    (nixago "configs")
    (anything "checks")
    (functions "nixosModules")
  ];
```

**`functions` for NixOS modules:** The `functions` block type is documented as "use this for all types of modules and profiles." It's a pass-through container with no actions or system-dependent behavior. Combined with `std.pick` (which strips the system prefix), it produces the correct `nixosModules.<name>` output shape.

## File Structure

```
cells/app/
├── devshells.nix             # Dev shell — references cell.configs.*, app + tool packages
├── configs.nix               # nixago block: treefmt, lefthook, conform, editorconfig
├── treefmt-formatters.nix    # Shared treefmt formatter defs (used by configs.nix + checks)
├── nixosModules.nix          # functions block: readaloud NixOS service module
├── checks/
│   ├── default.nix           # Re-exports all checks (except e2e)
│   ├── formatting.nix        # treefmt --fail-on-change (nixfmt, biome, mix format)
│   ├── statix.nix            # statix check
│   ├── deadnix.nix           # deadnix check
│   ├── biome-lint.nix        # biome lint check
│   ├── credo.nix             # mix credo --strict (reuses fetchMixDeps)
│   └── e2e.nix               # NixOS VM test (KVM, not wired up)
├── packages/
│   ├── default.nix           # Re-exports readaloud as default
│   └── readaloud/
│       └── default.nix       # mixRelease build (unchanged)
```

**Renamed:** `nixos.nix` → `nixosModules.nix` (matches `functions "nixosModules"` block type)

**New:** `configs.nix`, `checks/` directory with per-check files (mirrors packages/ structure)

**Deleted:** inline nixago configs from devshells.nix (moved to configs.nix)

## flake.nix

```nix
{
  description = "ReadAloud — audiobook generation and reading companion";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    hive = {
      url = "github:divnix/hive";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std.follows = "hive/std";
  };

  outputs =
    { self, std, nixpkgs, hive, ... }@inputs:
    hive.growOn
      {
        inherit inputs;
        systems = [ "x86_64-linux" ];
        cellsFrom = ./cells;
        cellBlocks =
          with std.blockTypes;
          [
            (devshells "devshells")
            (installables "packages")
            (nixago "configs")
            (anything "checks")
            (functions "nixosModules")
          ];
      }
      {
        devShells = std.harvest self [ "app" "devshells" ];
        packages = std.harvest self [ "app" "packages" ];
        checks = std.harvest self [ "app" "checks" ];
        nixosModules = std.pick self [ "app" "nixosModules" ];
      };
}
```

**Changes from current flake.nix:**
- `hive.growOn` instead of `std.growOn`
- `std.harvest` for devShells, packages, checks (per-system outputs)
- `std.pick` for nixosModules (system-independent — strips system prefix)
- No `eachSystem`, no `treefmtEval`, no `runCommand` — all moved to cells
- No `formatter` output — use `treefmt` from devshell
- Single soil layer — all outputs harvested via `std.harvest` or `std.pick`
- No e2e-test output — `checks/e2e.nix` kept in repo but not wired up until KVM is available

## cells/app/configs.nix (nixago block)

```nix
{ inputs, cell }:
let
  inherit (inputs) nixpkgs;
  inherit (inputs.std.lib.dev) mkNixago;
  l = nixpkgs.lib;
in
{
  treefmt = mkNixago {
    data = { formatter = import ./treefmt-formatters.nix { inherit nixpkgs l; }; };
    output = "treefmt.toml";
    format = "toml";
  };

  lefthook = mkNixago {
    data = {
      pre-commit = {
        commands = {
          treefmt = {
            run = "${l.getExe nixpkgs.treefmt} --fail-on-change";
          };
        };
      };
      commit-msg = {
        commands = {
          conform = {
            run = "${l.getExe nixpkgs.conform} enforce --commit-msg-file {1}";
          };
        };
      };
    };
    output = "lefthook.yml";
    format = "yaml";
    hook.extra = _: ''
      ${l.getExe nixpkgs.lefthook} install
    '';
  };

  conform = mkNixago {
    data = {
      policies = [
        {
          type = "commit";
          spec = {
            header = {
              length = 72;
              imperative = true;
              case = "lower";
              invalidLastCharacters = ".";
            };
            body.required = false;
            conventional = {
              types = [ "feat" "fix" "chore" "docs" "refactor" "test" "ci" "style" "perf" ];
              scopes = [ ".*" ];
            };
          };
        }
      ];
    };
    output = ".conform.yaml";
    format = "yaml";
  };

  editorconfig = mkNixago {
    data = {
      root = true;
      "*" = {
        end_of_line = "lf";
        insert_final_newline = true;
        trim_trailing_whitespace = true;
        charset = "utf-8";
      };
      "*.{nix,ex,exs,js,css,heex}" = {
        indent_style = "space";
        indent_size = 2;
      };
    };
    output = ".editorconfig";
    engine =
      request:
      let
        inherit (request) data output;
        name = nixpkgs.lib.baseNameOf output;
        value = {
          globalSection = { root = data.root or true; };
          sections = nixpkgs.lib.removeAttrs data [ "root" ];
        };
      in
      nixpkgs.writeText name (nixpkgs.lib.generators.toINIWithGlobalSection { } value);
  };
}
```

**eclint replaced:** Removed from treefmt formatters. Editorconfig enforcement is via `editorconfig-checker` (the engine in the editorconfig nixago config validates format; for CI, the checks block can add a check if needed). eclint is unmaintained since 2020.

## cells/app/treefmt-formatters.nix (shared)

```nix
{ nixpkgs, l }:
{
  nixfmt = {
    command = l.getExe nixpkgs.nixfmt;
    includes = [ "*.nix" ];
  };
  biome = {
    command = l.getExe nixpkgs.biome;
    options = [ "format" "--write" ];
    includes = [ "*.js" ];
  };
  mix-format = {
    command = "mix";
    options = [ "format" ];
    includes = [ "*.ex" "*.exs" ];
  };
}
```

Not a cell block — a plain Nix file imported by both `configs.nix` (nixago treefmt) and `checks/formatting.nix` (CI check). Single source of truth for formatter definitions.

## cells/app/checks/ (anything block — directory structure)

### checks/default.nix

```nix
{ inputs, cell }:
let
  inherit (inputs) nixpkgs;
  self = inputs.self;
  l = nixpkgs.lib;
  beamPackages = nixpkgs.beam.packagesWith nixpkgs.beam.interpreters.erlang_27;

  # Reuse the fetchMixDeps from the package build via passthru — single source of truth.
  inherit (cell.packages.readaloud.passthru) mixFodDeps;

  # Shared treefmt formatter definitions — same file used by configs.nix
  treefmtData = { formatter = import ../treefmt-formatters.nix { inherit nixpkgs l; }; };
in
{
  formatting = import ./formatting.nix { inherit nixpkgs self l treefmtData; };
  statix = import ./statix.nix { inherit nixpkgs self; };
  deadnix = import ./deadnix.nix { inherit nixpkgs self; };
  biome-lint = import ./biome-lint.nix { inherit nixpkgs self; };
  credo = import ./credo.nix { inherit nixpkgs self beamPackages mixFodDeps; };
}
```

### checks/formatting.nix

```nix
{ nixpkgs, self, l, treefmtData }:
let
  # Generate treefmt.toml from the same data as configs.nix nixago block.
  # Single source of truth — no duplicated formatter definitions.
  treefmtConfig = (nixpkgs.formats.toml { }).generate "treefmt.toml" treefmtData;
  beamPackages = nixpkgs.beam.packagesWith nixpkgs.beam.interpreters.erlang_27;
in
nixpkgs.runCommand "formatting-check" {
  # treefmt.toml references absolute store paths for commands, but
  # nativeBuildInputs ensures the tools are built and available.
  nativeBuildInputs = [ nixpkgs.treefmt nixpkgs.nixfmt nixpkgs.biome beamPackages.elixir ];
} ''
  cp -r ${self} source && chmod -R +w source && cd source
  export HOME=$TMPDIR
  cp ${treefmtConfig} treefmt.toml
  treefmt --no-cache --fail-on-change
  touch $out
''
```

### checks/statix.nix

```nix
{ nixpkgs, self }:
nixpkgs.runCommand "statix-check" {
  nativeBuildInputs = [ nixpkgs.statix ];
} ''
  cd ${self}
  statix check .
  touch $out
''
```

### checks/deadnix.nix

```nix
{ nixpkgs, self }:
nixpkgs.runCommand "deadnix-check" {
  nativeBuildInputs = [ nixpkgs.deadnix ];
} ''
  cd ${self}
  deadnix --fail -L .
  touch $out
''
```

### checks/biome-lint.nix

```nix
{ nixpkgs, self }:
nixpkgs.runCommand "biome-lint-check" {
  nativeBuildInputs = [ nixpkgs.biome ];
} ''
  cd ${self}
  biome lint apps/readaloud_web/assets/js/
  touch $out
''
```

### checks/credo.nix

```nix
{ nixpkgs, self, beamPackages, mixFodDeps }:
nixpkgs.runCommand "credo-check" {
  nativeBuildInputs = [ beamPackages.elixir beamPackages.erlang beamPackages.hex beamPackages.rebar3 ];
} ''
  cp -r ${self} source && chmod -R +w source && cd source
  export HOME=$TMPDIR
  export HEX_HOME="$TMPDIR/.hex"
  export MIX_HOME="$TMPDIR/.mix"
  export MIX_ENV=dev
  export MIX_DEPS_PATH="$TMPDIR/deps"
  export REBAR_GLOBAL_CONFIG_DIR="$TMPDIR/rebar3"
  export REBAR_CACHE_DIR="$TMPDIR/rebar3.cache"
  cp --no-preserve=mode -R ${mixFodDeps} "$MIX_DEPS_PATH"
  mix deps.compile --no-deps-check
  mix credo --strict
  touch $out
''
```

**Directory structure mirrors packages/.** Each check is a separate file imported by `default.nix`. The e2e test (`checks/e2e.nix`) is excluded from the default attrset — requires KVM, not wired up.

**Sandbox strategies:**
- **treefmt.toml:** gitignored (nixago-generated), so the formatting check generates its own via `pkgs.formats.toml`. Now includes `mix format` since Elixir is available.
- **credo:** Accesses `mixFodDeps` via `cell.packages.readaloud.passthru.mixFodDeps` — single source of truth, no duplicated hash.

**Package change required:** Add `passthru = { inherit mixFodDeps; };` to the `mixRelease` call in `packages/readaloud/default.nix` to expose the deps derivation.

## cells/app/devshells.nix (simplified)

```nix
{ inputs, cell }:
let
  inherit (inputs) nixpkgs;
  inherit (inputs.std) lib;
  inherit (inputs) std;
  l = nixpkgs.lib;
  beamPackages = nixpkgs.beam.packagesWith nixpkgs.beam.interpreters.erlang_27;
in
{
  default = lib.dev.mkShell {
    name = "readaloud-dev";

    imports = [ std.std.devshellProfiles.default ];

    nixago = [
      cell.configs.treefmt
      cell.configs.lefthook
      cell.configs.conform
      cell.configs.editorconfig
    ];

    packages = [
      # App deps — use same beamPackages as package build for version consistency
      beamPackages.elixir
      beamPackages.erlang
      nixpkgs.nodejs_22
      nixpkgs.sqlite
      nixpkgs.calibre
      nixpkgs.poppler-utils
      nixpkgs.inotify-tools

      # Dev tools — nixago generates config files and runs hooks,
      # but does NOT add tool binaries to PATH. Must be explicit.
      nixpkgs.treefmt
      nixpkgs.nixfmt
      nixpkgs.biome
      nixpkgs.statix
      nixpkgs.deadnix
      nixpkgs.lefthook
      nixpkgs.conform
    ];

    env = [
      { name = "MIX_HOME"; eval = "$PWD/.mix"; }
      { name = "HEX_HOME"; eval = "$PWD/.hex"; }
      { name = "MIX_ENV"; value = "dev"; }
    ];

    commands = [
      {
        name = "setup";
        help = "Bootstrap Hex and Rebar";
        command = "mix local.hex --if-missing && mix local.rebar --if-missing";
      }
      {
        name = "fmt";
        help = "Format all code";
        command = "${l.getExe nixpkgs.treefmt}";
      }
      {
        name = "lint";
        help = "Run all linters";
        command = "${l.getExe nixpkgs.statix} check . && ${l.getExe nixpkgs.deadnix} . && ${l.getExe nixpkgs.biome} lint apps/readaloud_web/assets/js/ && mix credo --strict";
      }
      {
        name = "check";
        help = "Run nix flake check";
        command = "nix flake check";
      }
    ];
  };
}
```

**Clarification on nixago and packages:** Nixago generates config files (treefmt.toml, lefthook.yml, etc.) and runs shell hooks on devshell entry. It does **not** add tool binaries to `$PATH`. Tool packages must be listed explicitly in `packages`, matching the configs reference pattern (`/home/noah/projects/configs/nix/core/shells.nix`).

**Moved to configs.nix:** Inline nixago config definitions (treefmt data, lefthook data, etc.). The devshell references them via `cell.configs.*`.

## cells/app/nixosModules.nix (functions block)

```nix
{ inputs, cell }:
{
  readaloud =
    { config, lib, pkgs, ... }:
    let
      cfg = config.services.readaloud;
      package = cell.packages.default;
    in
    {
      options.services.readaloud = {
        enable = lib.mkEnableOption "ReadAloud audiobook service";
        port = lib.mkOption { type = lib.types.port; default = 4000; description = "Phoenix web server port"; };
        host = lib.mkOption { type = lib.types.str; default = "localhost"; description = "PHX_HOST hostname"; };
        dataDir = lib.mkOption { type = lib.types.path; default = "/var/lib/readaloud"; description = "Persistent data directory"; };
        localaiUrl = lib.mkOption { type = lib.types.str; default = "http://localhost:8080"; description = "LocalAI service URL"; };
        secretKeyBaseFile = lib.mkOption { type = lib.types.path; description = "File containing SECRET_KEY_BASE"; };
      };

      config = lib.mkIf cfg.enable {
        users.users.readaloud = { isSystemUser = true; group = "readaloud"; home = cfg.dataDir; };
        users.groups.readaloud = { };

        systemd.services.readaloud = {
          description = "ReadAloud Audiobook Service";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];

          environment = {
            DATABASE_PATH = "${cfg.dataDir}/readaloud.db";
            PHX_HOST = cfg.host;
            PORT = toString cfg.port;
            LOCALAI_URL = cfg.localaiUrl;
            RELEASE_TMP = "/tmp/readaloud";
          };

          path = with pkgs; [ calibre poppler-utils ];

          serviceConfig = {
            Type = "exec";
            User = "readaloud";
            Group = "readaloud";
            StateDirectory = "readaloud";
            RuntimeDirectory = "readaloud";
            WorkingDirectory = cfg.dataDir;
            ExecStartPre = "${package}/bin/readaloud eval 'ReadaloudLibrary.Release.migrate()'";
            ExecStop = "${package}/bin/readaloud stop";
            Restart = "on-failure";
            RestartSec = 5;
            LoadCredential = "secret_key_base:${cfg.secretKeyBaseFile}";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            ReadWritePaths = [ cfg.dataDir ];
          };

          script = ''
            export SECRET_KEY_BASE="$(cat $CREDENTIALS_DIRECTORY/secret_key_base)"
            exec ${package}/bin/readaloud start
          '';
        };
      };
    };
}
```

**Key changes from current nixos.nix:**
- Now a proper cell block function (`{ inputs, cell }:`) instead of `{ package }:`
- Uses `cell.packages.default` to access the package (no hardcoded system string)
- Harvested via `std.pick self ["app" "nixosModules"]` — produces `nixosModules.readaloud` (system-independent)
- `std.pick` works because `functions` blocks produce identical values across all systems — it safely grabs the first system's result

## Decisions

| Decision | Rationale |
|----------|-----------|
| Drop `treefmt-nix` | Single treefmt config in nixago, no duplication; CI check generates its own config |
| `std.follows = "hive/std"` | std comes through hive (includes devshell + nixago integrations automatically) |
| `(functions "nixosModules")` + `std.pick` | `functions` is documented for modules/profiles; `std.pick` strips system prefix for system-independent output |
| `(anything "checks")` for checks | Harvestable block type for derivation-based checks |
| `checks/` directory structure | Mirrors `packages/` pattern — `default.nix` re-exports, individual check files |
| Remove eclint | Unmaintained since 2020; editorconfig validated by custom engine |
| Drop `formatter` output | `treefmt` available in devshell; `nix fmt` is redundant |
| Keep tool packages in devshells.nix | Nixago generates config files and runs hooks, but may not add binaries to PATH (verify in practice) |
| Generate treefmt.toml in checks | `treefmt.toml` is gitignored (nixago-generated); CI check uses `pkgs.formats.toml` to create config inline |
| `cell.packages.default` in nixos module | Avoids hardcoded system string; accessed through cell's own block |
| e2e-test not wired up | KVM not available (BIOS SVM disabled); `checks/e2e.nix` kept in repo for future use |
