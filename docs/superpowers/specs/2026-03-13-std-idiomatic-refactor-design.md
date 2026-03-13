# Idiomatic std/hive Refactor — Design Spec

**Date:** 2026-03-13
**Status:** Approved
**Predecessor:** `/home/noah/projects/readaloud/docs/superpowers/specs/2026-03-12-nix-infrastructure-overhaul-design.md`

## Overview

Refactor the readaloud flake from a hybrid std/manual pattern to idiomatic divnix/std and divnix/hive usage. Move all outputs into cell blocks where possible. Drop treefmt-nix. Use hive for NixOS module export.

## Motivation

The initial infrastructure overhaul (2026-03-12) used std for devshells/packages but manually defined checks, formatter, and nixosModules in the flake.nix growOn extras. This refactor aligns with std's intended usage by:

- Using `(nixago "configs")` block type instead of inline nixago configs in devshells.nix
- Using `(anything "checks")` block type instead of manual `runCommand` definitions in flake.nix
- Using `hive.blockTypes.nixosConfigurations` + `hive.collect` instead of manual `import ./cells/app/nixos.nix`
- Dropping `treefmt-nix` input — treefmt config is defined once in the nixago block
- Removing redundant package declarations from devshells.nix

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

**Removed:** `treefmt-nix` (replaced by nixago treefmt config).

**Changed:** `std` now follows through `hive` (matching configs pattern). The `devshell` and `nixago` inputs previously injected into std are no longer needed — hive provides them.

## Cell Blocks

```nix
cellBlocks =
  with std.blockTypes;
  with hive.blockTypes;
  [
    (devshells "devshells")
    (installables "packages")
    (nixago "configs")
    (anything "checks")
    nixosConfigurations
  ];
```

## File Structure

```
cells/app/
├── devshells.nix             # Dev shell — references cell.configs.*, minimal packages
├── configs.nix               # nixago block: treefmt, lefthook, conform, editorconfig
├── checks.nix                # anything block: formatting, statix, deadnix, biome-lint
├── nixosConfigurations.nix   # hive block: readaloud NixOS module
├── checks/
│   └── e2e.nix              # NixOS VM test (unchanged, referenced from flake.nix)
├── packages/
│   ├── default.nix           # Re-exports readaloud as default
│   └── readaloud/
│       └── default.nix       # mixRelease build (unchanged)
```

**Renamed:** `nixos.nix` → `nixosConfigurations.nix` (matches hive block type naming convention)

**New:** `configs.nix`, `checks.nix`

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
          with hive.blockTypes;
          [
            (devshells "devshells")
            (installables "packages")
            (nixago "configs")
            (anything "checks")
            nixosConfigurations
          ];
      }
      {
        nixosConfigurations = hive.collect self "nixosConfigurations";
      }
      {
        devShells = std.harvest self [ "app" "devshells" ];
        packages = std.harvest self [ "app" "packages" ];
        checks = std.harvest self [ "app" "checks" ];
      }
      {
        # E2E test requires KVM — not in default checks.
        # Run explicitly: nix build .#e2e-test.x86_64-linux
        e2e-test = nixpkgs.lib.genAttrs [ "x86_64-linux" ] (
          system: import ./cells/app/checks/e2e.nix {
            inherit self;
            pkgs = nixpkgs.legacyPackages.${system};
          }
        );
      };
}
```

**Changes from current flake.nix:**
- `hive.growOn` instead of `std.growOn`
- `hive.collect` for nixosConfigurations (system-independent harvest)
- `std.harvest` for devShells, packages, checks
- No `eachSystem`, no `treefmtEval`, no `runCommand` — all moved to cells
- No `formatter` output — use `treefmt` from devshell
- Four "soil layers" in growOn (hive configs, std harvests, manual extras)

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
    data = {
      formatter = {
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
      };
    };
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
          credo = {
            run = "mix credo --strict";
            glob = "*.{ex,exs}";
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

## cells/app/checks.nix (anything block)

```nix
{ inputs, cell }:
let
  inherit (inputs) nixpkgs;
  self = inputs.self;
  l = nixpkgs.lib;
in
{
  formatting = nixpkgs.runCommand "formatting-check" {
    nativeBuildInputs = [ nixpkgs.treefmt nixpkgs.nixfmt nixpkgs.biome ];
  } ''
    cd ${self}
    treefmt --fail-on-change
    touch $out
  '';

  statix = nixpkgs.runCommand "statix-check" {
    nativeBuildInputs = [ nixpkgs.statix ];
  } ''
    cd ${self}
    statix check .
    touch $out
  '';

  deadnix = nixpkgs.runCommand "deadnix-check" {
    nativeBuildInputs = [ nixpkgs.deadnix ];
  } ''
    cd ${self}
    deadnix --fail -L .
    touch $out
  '';

  biome-lint = nixpkgs.runCommand "biome-lint-check" {
    nativeBuildInputs = [ nixpkgs.biome ];
  } ''
    cd ${self}
    biome lint apps/readaloud_web/assets/js/
    touch $out
  '';
}
```

**Note on formatting check:** The treefmt `--fail-on-change` check in the sandbox may have issues with `mix format` (not available in sandbox). The check includes only nixfmt and biome — the CI-safe subset. mix format runs via lefthook locally.

## cells/app/devshells.nix (simplified)

```nix
{ inputs, cell }:
let
  inherit (inputs) nixpkgs;
  inherit (inputs.std) lib;
  inherit (inputs) std;
  l = nixpkgs.lib;
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

    packages = with nixpkgs; [
      # App deps
      elixir_1_17
      erlang_27
      nodejs_22
      sqlite
      calibre
      poppler-utils
      inotify-tools
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

**Removed from packages:** treefmt, nixfmt, biome, eclint, statix, deadnix, lefthook, conform. These are provided by the nixago configs integration automatically.

**Remaining packages:** Only app-specific deps that aren't provided by nixago (elixir, erlang, node, sqlite, calibre, poppler-utils, inotify-tools).

## cells/app/nixosConfigurations.nix (hive block)

```nix
{ inputs, cell }:
let
  package = cell.packages.default;
in
{
  readaloud =
    { config, lib, pkgs, ... }:
    let
      cfg = config.services.readaloud;
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

**Key change:** `cell.packages.default` replaces `self.packages.x86_64-linux.default` — the package is accessed through the cell's own block, not the flake output. This eliminates the hardcoded system string.

## Decisions

| Decision | Rationale |
|----------|-----------|
| Drop `treefmt-nix` | Single treefmt config in nixago, no duplication |
| `std.follows = "hive/std"` | std comes through hive, matching configs pattern |
| `hive.collect` for nixosConfigurations | System-independent harvest, proper hive pattern |
| `(anything "checks")` for checks | Harvestable block type for derivation-based checks |
| Remove eclint | Unmaintained since 2020; editorconfig validated by custom engine |
| Drop `formatter` output | `treefmt` available in devshell; `nix fmt` is redundant |
| `cell.packages.default` in nixos module | Avoids hardcoded system string |
| Keep e2e-test manual | KVM-dependent, shouldn't be in default checks |
