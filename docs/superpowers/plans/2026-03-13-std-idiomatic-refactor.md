# Idiomatic std/hive Refactor — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor readaloud's Nix flake from hybrid std/manual to idiomatic divnix/std + divnix/hive with all outputs as harvested cell blocks.

**Architecture:** Switch from `std.growOn` to `hive.growOn`. Move inline nixago configs and checks into dedicated cell blocks. Use `(functions "nixosModules")` + `std.pick` for system-independent NixOS module harvesting. Drop `treefmt-nix` input — treefmt config lives in the nixago block.

**Tech Stack:** Nix, divnix/std, divnix/hive, nixago, treefmt, Elixir/Phoenix (beamPackages)

**Spec:** `/home/noah/projects/readaloud/.worktrees/nix-infrastructure/docs/superpowers/specs/2026-03-13-std-idiomatic-refactor-design.md`

**Working directory:** `/home/noah/projects/readaloud/.worktrees/nix-infrastructure`

**Branch:** `feature/nix-infrastructure`

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Create | `cells/app/treefmt-formatters.nix` | Shared treefmt formatter definitions |
| Create | `cells/app/configs.nix` | Nixago block: treefmt, lefthook, conform, editorconfig |
| Create | `cells/app/checks/default.nix` | Checks block: re-exports individual checks |
| Create | `cells/app/checks/formatting.nix` | Treefmt formatting check (sandbox) |
| Create | `cells/app/checks/statix.nix` | Statix linter check |
| Create | `cells/app/checks/deadnix.nix` | Deadnix unused code check |
| Create | `cells/app/checks/biome-lint.nix` | Biome JS linter check |
| Create | `cells/app/checks/credo.nix` | Elixir credo check (sandbox, uses fetchMixDeps) |
| Create | `cells/app/nixosModules.nix` | Functions block: NixOS service module |
| Modify | `cells/app/packages/readaloud/default.nix` | Add `passthru = { inherit mixFodDeps; }` |
| Modify | `cells/app/devshells.nix` | Remove inline configs, reference `cell.configs.*`, use beamPackages |
| Modify | `flake.nix` | Switch to hive.growOn, new inputs, new cellBlocks, harvest/pick |
| Keep   | `cells/app/checks/e2e.nix` | Unchanged (KVM test, not wired up) |
| Delete | `cells/app/nixos.nix` | Replaced by `nixosModules.nix` |

---

## Chunk 1: Scaffold and Switch

### Task 1: Research — verify treefmt-in-sandbox pattern

Before implementing, confirm the nixago treefmt + sandbox check approach is used by others in the std ecosystem. This avoids building something novel when a simpler pattern exists.

**Files:** None (research only)

- [ ] **Step 1: Search sourcegraph for std treefmt check patterns**

Search sourcegraph.com for Nix repos using std/nixago with treefmt checks. Look for:
- `mkNixago` + `treefmt` + `runCommand` (our pattern)
- `treefmt-nix` alongside std (the pattern we're replacing)
- Any simpler approach we're missing

Run:
```bash
# Search for repos using std with treefmt checks
open https://sourcegraph.com/search?q=context:global+mkNixago+treefmt+lang:nix&patternType=literal
open https://sourcegraph.com/search?q=context:global+std.blockTypes+treefmt+lang:nix&patternType=literal
```

- [ ] **Step 2: Document findings**

If a simpler common pattern exists, update the checks approach before proceeding. If our approach is reasonable (or no clear consensus), continue as designed.

Note: If the research shows that keeping `treefmt-nix` for CI checks alongside nixago treefmt for devshell is the common pattern, we can keep both — the spec's approach is more elegant but may not be battle-tested.

---

### Task 2: Create `cells/app/treefmt-formatters.nix`

Shared formatter definitions used by both `configs.nix` (nixago devshell) and `checks/formatting.nix` (CI sandbox check).

**Files:**
- Create: `cells/app/treefmt-formatters.nix`

- [ ] **Step 1: Write the file**

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

- [ ] **Step 2: Verify syntax**

Run: `nix-instantiate --parse cells/app/treefmt-formatters.nix`
Expected: parsed expression, no errors

---

### Task 3: Create `cells/app/configs.nix`

Nixago block — generates config files (treefmt.toml, lefthook.yml, .conform.yaml, .editorconfig) on devshell entry.

**Files:**
- Create: `cells/app/configs.nix`

- [ ] **Step 1: Write the file**

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

- [ ] **Step 2: Verify syntax**

Run: `nix-instantiate --parse cells/app/configs.nix`
Expected: parsed expression, no errors

---

### Task 4: Create `cells/app/checks/` directory

Check derivations run by `nix flake check`. Each check is a separate file.

**Files:**
- Create: `cells/app/checks/default.nix`
- Create: `cells/app/checks/formatting.nix`
- Create: `cells/app/checks/statix.nix`
- Create: `cells/app/checks/deadnix.nix`
- Create: `cells/app/checks/biome-lint.nix`
- Create: `cells/app/checks/credo.nix`

- [ ] **Step 1: Create checks directory**

Run: `mkdir -p cells/app/checks`

- [ ] **Step 2: Move e2e.nix into checks/**

The e2e test already exists at `cells/app/checks/e2e.nix`. Verify it's there:
Run: `ls cells/app/checks/e2e.nix`
Expected: file exists

- [ ] **Step 3: Write `checks/formatting.nix`**

```nix
{ nixpkgs, self, l, treefmtData }:
let
  treefmtConfig = (nixpkgs.formats.toml { }).generate "treefmt.toml" treefmtData;
  beamPackages = nixpkgs.beam.packagesWith nixpkgs.beam.interpreters.erlang_27;
in
nixpkgs.runCommand "formatting-check" {
  nativeBuildInputs = [ nixpkgs.treefmt nixpkgs.nixfmt nixpkgs.biome beamPackages.elixir ];
} ''
  cp -r ${self} source && chmod -R +w source && cd source
  export HOME=$TMPDIR
  cp ${treefmtConfig} treefmt.toml
  treefmt --no-cache --fail-on-change
  touch $out
''
```

- [ ] **Step 4: Write `checks/statix.nix`**

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

- [ ] **Step 5: Write `checks/deadnix.nix`**

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

- [ ] **Step 6: Write `checks/biome-lint.nix`**

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

- [ ] **Step 7: Write `checks/credo.nix`**

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

- [ ] **Step 8: Write `checks/default.nix`**

```nix
{ inputs, cell }:
let
  inherit (inputs) nixpkgs;
  self = inputs.self;
  l = nixpkgs.lib;
  beamPackages = nixpkgs.beam.packagesWith nixpkgs.beam.interpreters.erlang_27;

  inherit (cell.packages.readaloud.passthru) mixFodDeps;

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

- [ ] **Step 9: Verify syntax of all check files**

Run: `for f in cells/app/checks/{default,formatting,statix,deadnix,biome-lint,credo}.nix; do echo "--- $f ---"; nix-instantiate --parse "$f" || echo "FAIL: $f"; done`
Expected: all parse successfully

---

### Task 5: Add `passthru` to package build

Expose `mixFodDeps` on the package derivation so checks can access it without duplicating the hash.

**Files:**
- Modify: `cells/app/packages/readaloud/default.nix`

- [ ] **Step 1: Add passthru to mixRelease call**

In `cells/app/packages/readaloud/default.nix`, add `passthru = { inherit mixFodDeps; };` inside the `mixRelease { ... }` block, after the `inherit mixFodDeps;` line.

Before:
```nix
beamPackages.mixRelease {
  pname = "readaloud";
  version = "0.1.0";
  src = inputs.self;

  inherit mixFodDeps;
```

After:
```nix
beamPackages.mixRelease {
  pname = "readaloud";
  version = "0.1.0";
  src = inputs.self;

  inherit mixFodDeps;
  passthru = { inherit mixFodDeps; };
```

- [ ] **Step 2: Verify syntax**

Run: `nix-instantiate --parse cells/app/packages/readaloud/default.nix`
Expected: no errors

---

### Task 6: Create `cells/app/nixosModules.nix`

Convert `nixos.nix` (function taking `{ package }`) to a proper cell block function taking `{ inputs, cell }`.

**Files:**
- Create: `cells/app/nixosModules.nix`

- [ ] **Step 1: Write the file**

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

Key changes from current `nixos.nix`:
- `{ inputs, cell }:` instead of `{ package }:`
- `package = cell.packages.default;` inside the module's `let` block
- Wrapped in `{ readaloud = ... }` attrset (the block exports an attrset of modules)

- [ ] **Step 2: Verify syntax**

Run: `nix-instantiate --parse cells/app/nixosModules.nix`
Expected: no errors

---

### Task 7: Atomic switch — update `flake.nix` and `devshells.nix`

This is the core refactor. Must happen atomically — flake.nix references new cell blocks, devshells.nix references `cell.configs.*`.

**Files:**
- Modify: `flake.nix`
- Modify: `cells/app/devshells.nix`
- Delete: `cells/app/nixos.nix`

- [ ] **Step 1: Update `flake.nix`**

Replace entire file with spec version (lines 87-123):
- Inputs: add `hive`, change `std.follows = "hive/std"`, remove `treefmt-nix` and old `std` with inline devshell/nixago
- Outputs: `hive.growOn` with new cellBlocks, `std.harvest` for devShells/packages/checks, `std.pick` for nixosModules
- Remove all manual extras (`eachSystem`, `treefmtEval`, `runCommand` checks, `formatter`, `e2e-test`)

- [ ] **Step 2: Update `cells/app/devshells.nix`**

Replace entire file with spec version (lines 377-449):
- Remove all inline nixago config definitions (treefmtConfig, lefthookConfig, etc.)
- Add `cell.configs.*` references in `nixago = [...]`
- Switch from `elixir_1_17`/`erlang_27` to `beamPackages.elixir`/`beamPackages.erlang`
- Remove `eclint` from packages
- Keep tool packages explicit (treefmt, nixfmt, biome, statix, deadnix, lefthook, conform)

- [ ] **Step 3: Delete old `cells/app/nixos.nix`**

Run: `rm cells/app/nixos.nix`

- [ ] **Step 4: Update flake lock**

Run: `nix flake lock`
Expected: lock file updated — adds `hive` input, updates `std` to follow through hive, removes `treefmt-nix`

Note: `nix flake lock` (no flags) resolves new inputs and prunes removed ones without updating existing inputs like `nixpkgs`. Do NOT use `nix flake update` — that updates ALL inputs including nixpkgs, risking unintended breakage.

---

### Task 8: Verify everything works

**Files:** None (verification only)

- [ ] **Step 1: Verify flake evaluation**

Run: `nix flake show 2>&1 | head -20`
Expected: shows `devShells`, `packages`, `checks`, `nixosModules` outputs

- [ ] **Step 2: Verify checks pass**

Run: `nix flake check 2>&1`
Expected: all checks pass (formatting, statix, deadnix, biome-lint, credo)

Note: credo check will be slow on first run (compiles all Mix deps in sandbox). If credo fails due to sandbox issues, investigate `MIX_DEPS_PATH` setup. Common issues:
- Missing hex/rebar3 in nativeBuildInputs
- `mixFodDeps` not being a writable copy (must `cp --no-preserve=mode`)
- Need `mix deps.compile --no-deps-check` before `mix credo`

- [ ] **Step 3: Verify devshell works**

Run: `nix develop -c bash -c 'echo "shell ok"; which treefmt; which mix; which lefthook'`
Expected: all tools found on PATH

- [ ] **Step 4: Verify nixago configs generated**

Run: `nix develop -c bash -c 'ls -la treefmt.toml lefthook.yml .conform.yaml .editorconfig'`
Expected: all config files exist (symlinks to nix store)

- [ ] **Step 5: Verify nixosModules export**

Run: `nix eval .#nixosModules.readaloud --apply 'x: builtins.typeOf x'`
Expected: `"lambda"` (it's a NixOS module function)

- [ ] **Step 6: Verify package still builds**

Run: `nix build .#default 2>&1 | tail -5`
Expected: builds successfully (or shows cached result)

- [ ] **Step 7: Fix any issues**

If any verification step fails:
1. Read the error carefully
2. Fix the issue in the relevant file
3. Re-run the failing verification step
4. Continue to next step

Common issues to watch for:
- `error: attribute 'conform' missing` — conform may not be in nixpkgs-unstable. Check with `nix eval nixpkgs#conform.meta.description 2>&1`. If missing, use `siderolabs/conform` or remove conform from packages/configs.
- `error: infinite recursion` — circular dependency between cell blocks (e.g., checks referencing packages which reference checks). Verify dependency graph is DAG.
- `hive.growOn: missing system` — ensure `systems = [ "x86_64-linux" ]` is in the growOn config.

---

### Task 9: Commit

- [ ] **Step 1: Stage and commit**

Must commit from within the devshell (lefthook needs `mix` in PATH):

```bash
nix develop -c bash -c '
  git add \
    cells/app/treefmt-formatters.nix \
    cells/app/configs.nix \
    cells/app/checks/default.nix \
    cells/app/checks/formatting.nix \
    cells/app/checks/statix.nix \
    cells/app/checks/deadnix.nix \
    cells/app/checks/biome-lint.nix \
    cells/app/checks/credo.nix \
    cells/app/nixosModules.nix \
    cells/app/packages/readaloud/default.nix \
    cells/app/devshells.nix \
    flake.nix \
    flake.lock
  git rm cells/app/nixos.nix
  git commit -m "refactor: idiomatic std/hive with cell blocks

Switch from std.growOn to hive.growOn. Move nixago configs,
checks, and NixOS module into proper cell blocks. Drop
treefmt-nix. Add credo and mix format as sandbox checks."
'
```

---

## Chunk 2: Post-Refactor Cleanup

### Task 10: Verify nixago auto-provides packages (optional)

The spec notes uncertainty about whether nixago configs automatically add tool binaries to `$PATH`. Test this during implementation.

**Files:**
- Possibly modify: `cells/app/devshells.nix`

- [ ] **Step 1: Test without explicit tool packages**

Temporarily remove `nixpkgs.treefmt`, `nixpkgs.nixfmt`, etc. from devshells.nix packages list. Enter the devshell and check if tools are on PATH:

```bash
nix develop -c bash -c 'which treefmt && which nixfmt && which lefthook'
```

- [ ] **Step 2: If tools are available without explicit packages**

Remove the duplicates from `packages` in devshells.nix and commit:
```bash
nix develop -c bash -c 'git add cells/app/devshells.nix && git commit -m "refactor: remove redundant tool packages from devshell"'
```

- [ ] **Step 3: If tools are NOT available**

Keep the explicit packages (current state). No changes needed.

---

### Task 11: Update `.gitignore` if needed

Nixago generates config files that should be gitignored (they're nix store symlinks).

**Files:**
- Possibly modify: `.gitignore`

- [ ] **Step 1: Check if generated configs are already gitignored**

Run: `git check-ignore treefmt.toml lefthook.yml .conform.yaml .editorconfig`
Expected: all listed (already gitignored)

- [ ] **Step 2: If not gitignored, add entries**

Add to `.gitignore`:
```
treefmt.toml
lefthook.yml
.conform.yaml
```

Note: `.editorconfig` should probably NOT be gitignored — editors need it even outside the devshell.

- [ ] **Step 3: Commit if changed**

```bash
nix develop -c bash -c 'git add .gitignore && git commit -m "chore: gitignore nixago generated configs"'
```
