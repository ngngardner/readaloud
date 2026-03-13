# Nix Infrastructure Overhaul Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the basic flake-utils flake with a divnix/std cell-based structure, adding linting, formatting, package build, flake checks, and a NixOS service module.

**Architecture:** Single `app/` cell under `cells/` using `std.growOn`. Dev shell with inline nixago configs (treefmt, lefthook, conform, editorconfig). `mixRelease` for the package build. NixOS module exported outside std in growOn extra outputs. treefmt-nix for formatter and formatting check.

**Tech Stack:** Nix (divnix/std, treefmt-nix, nixago), Elixir (mixRelease, credo, dialyzer), biome, statix, deadnix, eclint, lefthook, conform

**Spec:** `/home/noah/projects/readaloud/docs/superpowers/specs/2026-03-12-nix-infrastructure-overhaul-design.md`

---

## Reference Files

These existing files are the canonical patterns to follow:

| File | Purpose |
|------|---------|
| `/home/noah/projects/monorepo/flake.nix` | std.growOn + treefmt-nix evalModule pattern |
| `/home/noah/projects/monorepo/cells/app/devshells.nix` | Inline nixago (lefthook, treefmt) + mkShell pattern |
| `/home/noah/projects/land/flake.nix` | std.growOn with installables + checks (tests as derivation) |
| `/home/noah/projects/land/cells/app/devshells.nix` | Nixago (lefthook, treefmt, vscode) + commands pattern |
| `/home/noah/projects/readaloud/flake.nix` | Current flake to replace |
| `/home/noah/projects/readaloud/config/runtime.exs` | Has TTS/STT env vars to clean up |
| `/home/noah/projects/readaloud/mix.exs` | Umbrella project with release config |

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `flake.nix` | Rewrite | std.growOn entry, treefmt-nix evalModule, checks, NixOS module export |
| `cells/app/devshells.nix` | Create | Dev shell, inline nixago configs (treefmt, lefthook, conform, editorconfig) |
| `cells/app/packages/default.nix` | Create | Re-export readaloud package as default |
| `cells/app/packages/readaloud/default.nix` | Create | mixRelease build definition |
| `cells/app/nixos.nix` | Create | NixOS module for services.readaloud |
| `config/runtime.exs` | Modify | Remove TTS_MODEL, TTS_VOICE, STT_MODEL env vars |

---

## Chunk 1: Foundation — flake.nix + dev shell

### Task 1: Create cell directory structure and stub devshell

**Files:**
- Create: `cells/app/devshells.nix`

- [ ] **Step 1: Create cells/app directory**

```bash
mkdir -p cells/app
```

- [ ] **Step 2: Write minimal devshells.nix with existing deps only**

Create `cells/app/devshells.nix` — a minimal shell that reproduces the current flake's functionality using std's `lib.dev.mkShell`. No nixago yet, just packages and env vars.

```nix
{
  inputs,
  cell,
}:
let
  inherit (inputs) nixpkgs;
  inherit (inputs.std) lib;
  std = inputs.std;
in
{
  default = lib.dev.mkShell {
    name = "readaloud-dev";

    imports = [
      std.std.devshellProfiles.default
    ];

    packages = with nixpkgs; [
      # Existing deps
      elixir_1_17
      erlang_27
      nodejs_22
      sqlite
      calibre
      poppler-utils
      inotify-tools
    ];

    env = [
      {
        name = "MIX_HOME";
        eval = "$PWD/.mix";
      }
      {
        name = "HEX_HOME";
        eval = "$PWD/.hex";
      }
      {
        name = "MIX_ENV";
        value = "dev";
      }
    ];

    commands = [
      {
        name = "setup";
        help = "Bootstrap Hex and Rebar";
        command = "mix local.hex --if-missing && mix local.rebar --if-missing";
      }
    ];
  };
}
```

- [ ] **Step 3: Commit**

```bash
git add cells/app/devshells.nix
git commit -m "chore: add minimal std devshell for readaloud"
```

### Task 2: Rewrite flake.nix with std.growOn

**Files:**
- Rewrite: `flake.nix`

- [ ] **Step 1: Replace flake.nix with std.growOn structure**

Replace the entire `flake.nix` with the std pattern. This initial version only has devshells — no packages, checks, or NixOS module yet. Note: the spec lists `functions "nixos"` as a block type, but the NixOS module is exported outside std in Task 9 because NixOS modules are system-independent.

```nix
{
  description = "ReadAloud — audiobook generation and reading companion";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    std = {
      url = "github:divnix/std";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      std,
      nixpkgs,
      treefmt-nix,
      ...
    }@inputs:
    let
      systems = [ "x86_64-linux" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      treefmtEval = eachSystem (
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );
    in
    std.growOn
      {
        inherit inputs;
        cellsFrom = ./cells;
        cellBlocks = with std.blockTypes; [
          (devshells "devshells")
        ];
      }
      {
        devShells = std.harvest self [
          "app"
          "devshells"
        ];
        formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);
        checks = eachSystem (pkgs: {
          formatting = treefmtEval.${pkgs.system}.config.build.check self;
        });
      };
}
```

- [ ] **Step 2: Test that the flake evaluates**

```bash
nix flake show
```

Expected: Shows `devShells.x86_64-linux.default`, `formatter.x86_64-linux`, `checks.x86_64-linux.formatting`

- [ ] **Step 3: Test entering the dev shell**

```bash
nix develop
```

Expected: Shell opens with elixir, erlang, node, sqlite, etc. available. `MIX_HOME` and `HEX_HOME` set correctly.

- [ ] **Step 4: Commit**

```bash
git add flake.nix flake.lock
git commit -m "chore: rewrite flake.nix with divnix/std growOn structure"
```

### Task 3: Add nixago configs to devshell (treefmt, lefthook, conform, editorconfig)

**Files:**
- Modify: `cells/app/devshells.nix`

- [ ] **Step 1: Add nixago config definitions and new tool packages**

Update `cells/app/devshells.nix` to include inline nixago configs for treefmt, lefthook, conform, and editorconfig. Add linting tool packages. Full file replacement:

```nix
{
  inputs,
  cell,
}:
let
  inherit (inputs) nixpkgs;
  inherit (inputs.std) lib;
  std = inputs.std;

  l = nixpkgs.lib;

  # Keep in sync with treefmt-nix evalModule in flake.nix
  treefmtConfig = {
    data = {
      formatter = {
        nixfmt = {
          command = l.getExe nixpkgs.nixfmt;
          includes = [ "*.nix" ];
        };
        biome = {
          command = l.getExe nixpkgs.biome;
          options = [
            "format"
            "--write"
          ];
          includes = [
            "*.js"
            "*.css"
          ];
        };
        mix-format = {
          command = "mix";
          options = [ "format" ];
          includes = [
            "*.ex"
            "*.exs"
          ];
        };
        eclint = {
          command = l.getExe nixpkgs.eclint;
          options = [ "-fix" ];
          includes = [
            "*.nix"
            "*.ex"
            "*.exs"
            "*.js"
            "*.css"
            "*.heex"
            "*.md"
            "*.yml"
            "*.yaml"
            "*.json"
          ];
        };
      };
    };
    output = "treefmt.toml";
    format = "toml";
  };

  lefthookConfig = {
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

  conformConfig = {
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
            body = {
              required = false;
            };
            conventional = {
              types = [
                "feat"
                "fix"
                "chore"
                "docs"
                "refactor"
                "test"
                "ci"
                "style"
                "perf"
              ];
              scopes = [ ".*" ];
            };
          };
        }
      ];
    };
    output = ".conform.yaml";
    format = "yaml";
  };

  editorconfigConfig = {
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
    format = "ini";
  };
in
{
  default = lib.dev.mkShell {
    name = "readaloud-dev";

    imports = [
      std.std.devshellProfiles.default
    ];

    nixago = [
      (lib.dev.mkNixago treefmtConfig)
      (lib.dev.mkNixago lefthookConfig)
      (lib.dev.mkNixago conformConfig)
      (lib.dev.mkNixago editorconfigConfig)
    ];

    packages = with nixpkgs; [
      # Existing deps
      elixir_1_17
      erlang_27
      nodejs_22
      sqlite
      calibre
      poppler-utils
      inotify-tools

      # Formatting and linting
      treefmt
      nixfmt
      biome
      eclint
      statix
      deadnix

      # Git hooks
      lefthook
      conform
    ];

    env = [
      {
        name = "MIX_HOME";
        eval = "$PWD/.mix";
      }
      {
        name = "HEX_HOME";
        eval = "$PWD/.hex";
      }
      {
        name = "MIX_ENV";
        value = "dev";
      }
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
        command = "${l.getExe nixpkgs.statix} check . && ${l.getExe nixpkgs.deadnix} . && ${l.getExe nixpkgs.biome} lint apps/readaloud_web/assets/js/ apps/readaloud_web/assets/css/";
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

- [ ] **Step 2: Update treefmt-nix evalModule in flake.nix to match nixago formatters**

Update the `treefmtEval` in `flake.nix` to include biome and eclint (keeping nixfmt). Keep in sync with nixago treefmt config in `cells/app/devshells.nix`:

```nix
      # Keep in sync with nixago treefmtConfig in cells/app/devshells.nix
      treefmtEval = eachSystem (
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          programs.biome = {
            enable = true;
            includes = [
              "*.js"
              "*.css"
            ];
          };
          settings.formatter.eclint = {
            command = pkgs.lib.getExe pkgs.eclint;
            options = [ "-fix" ];
            includes = [
              "*.nix"
              "*.ex"
              "*.exs"
              "*.js"
              "*.css"
              "*.heex"
              "*.md"
              "*.yml"
              "*.yaml"
              "*.json"
            ];
          };
        }
      );
```

**Note:** `mix format` is deliberately excluded from treefmt-nix evalModule — it requires the full Elixir toolchain and project deps, which is impractical in the Nix sandbox. It is included in the nixago treefmt.toml (for local dev use where `mix` is available) and runs via lefthook pre-commit.

- [ ] **Step 3: Add statix and deadnix checks to flake.nix**

Add to the `checks` attrset in `flake.nix`:

```nix
        checks = eachSystem (pkgs: {
          formatting = treefmtEval.${pkgs.system}.config.build.check self;
          statix = pkgs.runCommand "statix-check" { nativeBuildInputs = [ pkgs.statix ]; } ''
            cd ${self}
            statix check .
            touch $out
          '';
          deadnix = pkgs.runCommand "deadnix-check" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
            cd ${self}
            deadnix .
            touch $out
          '';
        });
```

- [ ] **Step 4: Enter dev shell, verify nixago generates configs**

```bash
nix develop
```

Expected: `treefmt.toml`, `lefthook.yml`, `.conform.yaml`, `.editorconfig` are generated. `lefthook install` runs.

- [ ] **Step 5: Verify treefmt works**

```bash
nix develop -c treefmt
```

Expected: Formats nix, js, css files without errors.

- [ ] **Step 6: Verify flake checks pass**

```bash
nix flake check
```

Expected: `formatting`, `statix`, `deadnix` checks pass.

- [ ] **Step 7: Commit**

```bash
git add cells/app/devshells.nix flake.nix
git commit -m "feat: add nixago configs (treefmt, lefthook, conform, editorconfig) and lint checks"
```

---

## Chunk 2: Package Build

### Task 4: Create mixRelease package build

**Files:**
- Create: `cells/app/packages/default.nix`
- Create: `cells/app/packages/readaloud/default.nix`
- Modify: `flake.nix` (add installables block type + harvest)

- [ ] **Step 1: Create packages directory structure**

```bash
mkdir -p cells/app/packages/readaloud
```

- [ ] **Step 2: Write the mixRelease build definition**

Create `cells/app/packages/readaloud/default.nix`:

```nix
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
    # After first build attempt, update this hash from the error message
    hash = "";
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
    tailwindcss
  ];

  # Override esbuild/tailwind download steps — use nixpkgs binaries
  ESBUILD_PATH = nixpkgs.lib.getExe nixpkgs.esbuild;
  TAILWIND_PATH = nixpkgs.lib.getExe nixpkgs.tailwindcss;
  MIX_ENV = "prod";

  preBuild = ''
    # Ensure esbuild and tailwind use nixpkgs binaries, not downloaded ones
    export MIX_ESBUILD_PATH="${nixpkgs.lib.getExe nixpkgs.esbuild}"
    export MIX_TAILWIND_PATH="${nixpkgs.lib.getExe nixpkgs.tailwindcss}"
  '';

  postBuild = ''
    mix assets.deploy
  '';

  # Runtime dependencies
  buildInputs = with nixpkgs; [
    openssl
    ncurses
    calibre
    poppler-utils
  ];

  # Release name matches the release defined in mix.exs
  releaseName = "readaloud";

  meta = {
    description = "ReadAloud — audiobook generation and reading companion";
    mainProgram = "readaloud";
  };
}
```

**Note:** The `hash` in `fetchMixDeps` is intentionally empty. The first build will fail with the correct hash — update it then. This is the standard workflow for `mixFodDeps`.

- [ ] **Step 3: Write the packages re-export**

Create `cells/app/packages/default.nix`. This file is the entry point for the `installables "packages"` block. It imports the readaloud subdirectory and re-exports it as both the named package and the default:

```nix
{
  inputs,
  cell,
}:
let
  readaloud = import ./readaloud { inherit inputs cell; };
in
{
  inherit readaloud;
  default = readaloud;
}
```

Verify with `nix flake show` after wiring up — if std auto-discovers `readaloud/default.nix` as a separate block entry (directory-based blocks), adjust accordingly.

- [ ] **Step 4: Add installables block type and harvest to flake.nix**

Update `flake.nix` cellBlocks:

```nix
        cellBlocks = with std.blockTypes; [
          (devshells "devshells")
          (installables "packages")
        ];
```

Add packages harvest:

```nix
        packages = std.harvest self [
          "app"
          "packages"
        ];
```

- [ ] **Step 5: Attempt first build to get deps hash**

```bash
nix build .#readaloud 2>&1 | grep "got:"
```

Expected: Build fails with a hash mismatch. Copy the `got: sha256-...` hash.

- [ ] **Step 6: Update the hash in packages/readaloud/default.nix**

Replace the empty `hash = "";` with the actual hash from step 5.

- [ ] **Step 7: Build again**

```bash
nix build .#readaloud
```

Expected: Build succeeds (or reveals next issue to fix — esbuild/tailwind paths, native deps, etc.). Iterate as needed.

- [ ] **Step 8: Verify the built release**

```bash
ls -la result/bin/
result/bin/readaloud version
```

Expected: Release binary exists and prints version.

- [ ] **Step 9: Commit**

```bash
git add cells/app/packages/ flake.nix
git commit -m "feat: add mixRelease package build for readaloud"
```

---

## Chunk 3: Flake Checks — Elixir Linting + Tests

### Task 5: Add credo to the project and flake check

**Files:**
- Modify: `apps/readaloud_web/mix.exs` (or umbrella root — add credo dep)
- Create: `.credo.exs`
- Modify: `flake.nix` (add credo check)

- [ ] **Step 1: Add credo dependency**

Check which mix.exs to modify — credo should be a dev-only dep at the umbrella root or in each app. Adding to umbrella root `mix.exs` `deps`:

```elixir
defp deps do
  [
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
  ]
end
```

- [ ] **Step 2: Fetch deps**

```bash
mix deps.get
```

- [ ] **Step 3: Generate default credo config with strict defaults**

```bash
mix credo gen.config
```

Then edit `.credo.exs` to set `strict: true` in the config.

- [ ] **Step 4: Run credo locally to see current state**

```bash
mix credo --strict
```

Expected: May report issues in existing code. Note them — they'll need fixing before the check can pass in CI.

- [ ] **Step 5: Fix any credo issues in existing code**

Address credo warnings/errors. Common ones: missing moduledocs, long lines, TODO comments. Fix iteratively.

- [ ] **Step 6: Add credo flake check**

First, add a `mixFodDeps` definition to the `let` block in `flake.nix` (alongside `treefmtEval`) so both the package build and checks can reference it:

```nix
      beamPkgs = eachSystem (pkgs: pkgs.beam.packagesWith pkgs.beam.interpreters.erlang_27);
      mixFodDeps = eachSystem (pkgs: beamPkgs.${pkgs.system}.fetchMixDeps {
        pname = "readaloud-deps";
        version = "0.1.0";
        src = self;
        hash = ""; # Same hash as in packages/readaloud/default.nix — keep in sync
      });
```

Then update `cells/app/packages/readaloud/default.nix` to use the same hash (or reference the flake-level deps). The hash must match.

Then add the credo check:

```nix
          credo = pkgs.runCommand "credo-check"
            {
              nativeBuildInputs = [ pkgs.elixir_1_17 pkgs.erlang_27 ];
              src = self;
            }
            ''
              cp -r $src/* .
              cp -r ${mixFodDeps.${pkgs.system}} deps
              export MIX_HOME=$(mktemp -d)
              export HEX_HOME=$(mktemp -d)
              mix local.hex --force --if-missing
              mix local.rebar --force --if-missing
              mix credo --strict
              touch $out
            '';
```

**Note:** This is the riskiest check. The exact invocation may need iteration — the sandbox has no network, so deps must be fully pre-fetched. If this approach doesn't work, fall back to running credo only via lefthook (local only).

- [ ] **Step 7: Verify credo check passes**

```bash
nix flake check
```

- [ ] **Step 8: Commit**

```bash
git add mix.exs mix.lock .credo.exs flake.nix apps/
git commit -m "feat: add credo static analysis with strict mode"
```

### Task 6: Add biome lint check

**Files:**
- Modify: `flake.nix` (add biome-lint check)

- [ ] **Step 1: Run biome lint locally to check current state**

```bash
nix develop -c biome lint apps/readaloud_web/assets/js/ apps/readaloud_web/assets/css/
```

Expected: May report lint issues. Note them.

- [ ] **Step 2: Fix any biome lint issues in JS/CSS**

Address biome warnings in the assets directory.

- [ ] **Step 3: Add biome lint check to flake.nix**

```nix
          biome-lint = pkgs.runCommand "biome-lint-check" { nativeBuildInputs = [ pkgs.biome ]; } ''
            cd ${self}
            biome lint apps/readaloud_web/assets/js/ apps/readaloud_web/assets/css/
            touch $out
          '';
```

- [ ] **Step 4: Verify flake check passes**

```bash
nix flake check
```

- [ ] **Step 5: Commit**

```bash
git add flake.nix apps/readaloud_web/assets/
git commit -m "feat: add biome lint check for JS/CSS"
```

### Task 7: Add mix test flake check

**Files:**
- Modify: `flake.nix` (add mix-test check)

- [ ] **Step 1: Add mix test check to flake.nix**

```nix
          mix-test = pkgs.runCommand "mix-test-check"
            {
              nativeBuildInputs = with pkgs; [ elixir_1_17 erlang_27 sqlite ];
              src = self;
            }
            ''
              cp -r $src/* .
              cp -r ${mixFodDeps.${pkgs.system}} deps
              export MIX_HOME=$(mktemp -d)
              export HEX_HOME=$(mktemp -d)
              export MIX_ENV=test
              mix local.hex --force --if-missing
              mix local.rebar --force --if-missing
              mix test
              touch $out
            '';
```

**Note:** Same caveats as credo — sandbox constraints apply. SQLite must be available for Ecto. If tests require network or external services (LocalAI), they'll need to be mocked or tagged for exclusion.

- [ ] **Step 2: Run tests locally to confirm baseline**

```bash
mix test
```

- [ ] **Step 3: Verify flake check passes**

```bash
nix flake check
```

- [ ] **Step 4: Commit**

```bash
git add flake.nix
git commit -m "feat: add mix test flake check"
```

### Task 8: Add dialyzer (attempt — may defer)

**Files:**
- Modify: umbrella root `mix.exs` (add dialyxir dep)
- Modify: `flake.nix` (add dialyzer check)

- [ ] **Step 1: Add dialyxir dependency**

Add to umbrella root `mix.exs` deps:

```elixir
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
```

- [ ] **Step 2: Fetch deps and build PLT locally**

```bash
mix deps.get
mix dialyzer --plt
```

Time this. If PLT build takes > 5 minutes, consider deferring the flake check.

- [ ] **Step 3: Run dialyzer locally**

```bash
mix dialyzer
```

Note any type errors that need fixing.

- [ ] **Step 4: Decide: add flake check or defer?**

If PLT build was fast enough (< 3 min), add a flake check similar to the credo one. If too slow, skip the flake check and only run dialyzer via lefthook pre-push or manually. Document the decision.

- [ ] **Step 5: Commit**

```bash
git add mix.exs mix.lock flake.nix
git commit -m "feat: add dialyzer type checking (flake check or local-only)"
```

---

## Chunk 4: NixOS Module + Cleanup

### Task 9: Create NixOS service module

**Files:**
- Create: `cells/app/nixos.nix`
- Modify: `flake.nix` (export nixosModules)

- [ ] **Step 1: Write the NixOS module**

Create `cells/app/nixos.nix`:

```nix
# This file is imported directly by flake.nix, not through std blocks.
# NixOS modules are system-independent and cannot go through std's per-system evaluation.
{ package }:
{ config, lib, pkgs, ... }:
let
  cfg = config.services.readaloud;
in
{
  options.services.readaloud = {
    enable = lib.mkEnableOption "ReadAloud audiobook service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
      description = "Port for the Phoenix web server";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "Hostname for the Phoenix web server (PHX_HOST)";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/readaloud";
      description = "Directory for persistent data (database, generated audio)";
    };

    localaiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:8080";
      description = "URL of the LocalAI service for TTS/STT";
    };

    secretKeyBaseFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the Phoenix SECRET_KEY_BASE";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.readaloud = {
      isSystemUser = true;
      group = "readaloud";
      home = cfg.dataDir;
    };
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
        PATH = lib.makeBinPath (with pkgs; [ calibre poppler-utils ]);
      };

      serviceConfig = {
        Type = "exec";
        User = "readaloud";
        Group = "readaloud";
        StateDirectory = "readaloud";
        RuntimeDirectory = "readaloud";
        WorkingDirectory = cfg.dataDir;

        ExecStartPre = "${package}/bin/readaloud eval 'ReadaloudLibrary.Release.migrate()'";
        # ExecStart is set by `script` below — do NOT also set it here
        ExecStop = "${package}/bin/readaloud stop";
        Restart = "on-failure";
        RestartSec = 5;

        # Read secret key from file
        LoadCredential = "secret_key_base:${cfg.secretKeyBaseFile}";

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfg.dataDir ];
      };

      # Inject SECRET_KEY_BASE from credential file, then exec the release
      script = ''
        export SECRET_KEY_BASE="$(cat $CREDENTIALS_DIRECTORY/secret_key_base)"
        exec ${package}/bin/readaloud start
      '';
    };
  };
}
```

- [ ] **Step 2: Export NixOS module in flake.nix**

Add to the `std.growOn` second argument (the extra outputs attrset), **outside** the `eachSystem` calls:

```nix
        nixosModules.readaloud = import ./cells/app/nixos.nix {
          package = self.packages.x86_64-linux.default;
        };
```

**Note:** This hardcodes x86_64-linux for the package. If multi-arch support is needed later, the module can accept `package` as an option instead.

- [ ] **Step 3: Verify the module evaluates**

```bash
nix flake show
```

Expected: Shows `nixosModules.readaloud` in the output.

- [ ] **Step 4: Commit**

```bash
git add cells/app/nixos.nix flake.nix
git commit -m "feat: add NixOS module for services.readaloud"
```

### Task 10: Clean up TTS/STT env vars from runtime.exs

**Files:**
- Modify: `config/runtime.exs`

- [ ] **Step 1: Remove TTS_MODEL, TTS_VOICE, STT_MODEL from runtime.exs**

In `config/runtime.exs`, change the `readaloud_tts` config block from:

```elixir
  config :readaloud_tts,
    base_url: System.get_env("LOCALAI_URL", "http://localai:8080"),
    tts_model: System.get_env("TTS_MODEL", "kokoro"),
    voice: System.get_env("TTS_VOICE", "af_heart"),
    stt_model: System.get_env("STT_MODEL", "whisper-large-v3")
```

To:

```elixir
  config :readaloud_tts,
    base_url: System.get_env("LOCALAI_URL", "http://localai:8080")
```

The TTS/STT model selection is managed through model profiles in the application, not infrastructure env vars.

- [ ] **Step 2: Update runtime.exs to read PORT from environment**

The NixOS module sets `PORT` env var, but `runtime.exs` currently hardcodes `port: 4000`. Update:

```elixir
  port = String.to_integer(System.get_env("PORT", "4000"))

  config :readaloud_web, ReadaloudWebWeb.Endpoint,
    url: [host: host, port: port],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true
```

- [ ] **Step 3: Check for code-level references to removed config keys**

Search for `Application.get_env(:readaloud_tts, :tts_model)`, `Application.get_env(:readaloud_tts, :voice)`, `Application.get_env(:readaloud_tts, :stt_model)`, and any `System.get_env("TTS_MODEL")` etc. in `apps/readaloud_tts/`. These may still exist in a `Config.from_env/0` function or similar. If found, update those call sites to use struct defaults or model profiles instead. This is a separate but related cleanup — if extensive, defer to a follow-up task.

- [ ] **Step 4: Verify the app still compiles**

```bash
MIX_ENV=prod mix compile
```

Expected: Compiles without errors.

- [ ] **Step 5: Commit**

```bash
git add config/runtime.exs
git commit -m "refactor: remove TTS/STT model env vars from runtime config

Model selection is managed through application-level model profiles,
not infrastructure environment variables."
```

### Task 11: Final verification

- [ ] **Step 1: Run full flake check**

```bash
nix flake check
```

Expected: All checks pass — formatting, statix, deadnix, biome-lint, credo, mix-test (and dialyzer if included).

- [ ] **Step 2: Verify nix build works**

```bash
nix build
```

Expected: Produces the OTP release in `result/`.

- [ ] **Step 3: Verify dev shell is complete**

```bash
nix develop -c bash -c "which elixir && which biome && which statix && which lefthook && which conform && which treefmt"
```

Expected: All tools found.

- [ ] **Step 4: Run treefmt on entire project**

```bash
nix develop -c treefmt
```

Expected: All files formatted, no changes needed.

- [ ] **Step 5: Verify nix flake show output**

```bash
nix flake show
```

Expected output includes:
- `checks.x86_64-linux.formatting`
- `checks.x86_64-linux.statix`
- `checks.x86_64-linux.deadnix`
- `checks.x86_64-linux.biome-lint`
- `checks.x86_64-linux.credo`
- `checks.x86_64-linux.mix-test`
- `devShells.x86_64-linux.default`
- `formatter.x86_64-linux`
- `nixosModules.readaloud`
- `packages.x86_64-linux.default`
- `packages.x86_64-linux.readaloud`

- [ ] **Step 6: Final commit if any fixups needed**

```bash
git add flake.nix cells/ config/
git commit -m "chore: final fixups for nix infrastructure overhaul"
```
