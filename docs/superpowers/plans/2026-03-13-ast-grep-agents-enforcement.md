# ast-grep AGENTS.md Rule Enforcement Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace soft AGENTS.md prose rules with hard ast-grep + grep CI gates enforced via Nix checks and lefthook pre-commit.

**Architecture:** ast-grep YAML rules in `rules/` for Elixir and HEEx (mapped as HTML), a grep companion linter defined via `writeShellScriptBin` in `cells/app/lint-grep.nix` for Phoenix component patterns and cross-node checks, a Nix check derivation at `cells/app/checks/ast-grep.nix`, and lefthook integration via `cells/app/configs.nix`.

**Tech Stack:** ast-grep 0.41.1, nixpkgs, divnix/std nixago, lefthook, bash/grep

**Spec:** `docs/superpowers/specs/2026-03-13-ast-grep-agents-enforcement-design.md`

---

## Chunk 1: ast-grep Elixir Rules

### Task 1: Scaffold sgconfig.yml and first rule

**Files:**
- Create: `sgconfig.yml`
- Create: `rules/elixir/no-string-to-atom.yml`

- [ ] **Step 1: Create sgconfig.yml**

```yaml
ruleDirs:
  - rules/elixir
  - rules/heex
languageGlobs:
  html:
    - "**/*.heex"
```

- [ ] **Step 2: Create rules/elixir/no-string-to-atom.yml**

```yaml
id: no-string-to-atom
language: elixir
severity: warning
rule:
  pattern: String.to_atom($A)
message: Avoid String.to_atom/1 — memory leak risk. Use String.to_existing_atom/1 or explicit mapping.
```

- [ ] **Step 3: Test the rule**

Create a temp file and verify ast-grep catches it:
```bash
echo 'String.to_atom("test")' > /tmp/test-rule.ex
cd /home/noah/projects/readaloud && ast-grep run --lang elixir --pattern 'String.to_atom($A)' /tmp/test-rule.ex
```
Expected: match on line 1.

- [ ] **Step 4: Commit**

```bash
git add sgconfig.yml rules/elixir/no-string-to-atom.yml
git commit -m "ci: scaffold ast-grep config and first rule (no-string-to-atom)"
```

### Task 2: Test-scoped rules (Process.sleep, Process.alive?)

**Files:**
- Create: `rules/elixir/no-process-sleep-in-tests.yml`
- Create: `rules/elixir/no-process-alive-in-tests.yml`

- [ ] **Step 1: Create rules/elixir/no-process-sleep-in-tests.yml**

```yaml
id: no-process-sleep-in-tests
language: elixir
severity: error
rule:
  pattern: Process.sleep($A)
files:
  - "test/**/*.exs"
message: Don't use Process.sleep/1 in tests. Use Process.monitor/1 + assert_receive or :sys.get_state/1 for synchronization.
```

- [ ] **Step 2: Create rules/elixir/no-process-alive-in-tests.yml**

```yaml
id: no-process-alive-in-tests
language: elixir
severity: error
rule:
  pattern: Process.alive?($A)
files:
  - "test/**/*.exs"
message: Don't use Process.alive?/1 in tests. Use Process.monitor/1 + assert_receive {:DOWN, ...}.
```

- [ ] **Step 3: Verify file scoping works**

```bash
echo 'Process.sleep(100)' > /tmp/not-test.ex
mkdir -p /tmp/test && echo 'Process.sleep(100)' > /tmp/test/a_test.exs
cd /home/noah/projects/readaloud && ast-grep scan 2>&1 | grep process-sleep
```
Expected: only the `test/a_test.exs` file matches, not `/tmp/not-test.ex`. (Clean up temp files after.)

- [ ] **Step 4: Commit**

```bash
git add rules/elixir/no-process-sleep-in-tests.yml rules/elixir/no-process-alive-in-tests.yml
git commit -m "ci: add ast-grep rules for Process.sleep/alive? in tests"
```

### Task 3: Deprecated Phoenix API rules

**Files:**
- Create: `rules/elixir/no-phoenix-view.yml`
- Create: `rules/elixir/no-form-for.yml`
- Create: `rules/elixir/no-inputs-for.yml`
- Create: `rules/elixir/no-live-redirect.yml`
- Create: `rules/elixir/no-live-patch.yml`
- Create: `rules/elixir/no-eex-sigil.yml`

- [ ] **Step 1: Create rules/elixir/no-phoenix-view.yml**

```yaml
id: no-phoenix-view
language: elixir
severity: error
rule:
  pattern: use Phoenix.View
message: Phoenix.View is removed. Use Phoenix.Component and ~H sigils.
```

- [ ] **Step 2: Create rules/elixir/no-form-for.yml**

```yaml
id: no-form-for
language: elixir
severity: error
rule:
  pattern: Phoenix.HTML.form_for($$$)
message: Phoenix.HTML.form_for is deprecated. Use to_form/2 + <.form for={@form}>.
```

- [ ] **Step 3: Create rules/elixir/no-inputs-for.yml**

```yaml
id: no-inputs-for
language: elixir
severity: error
rule:
  pattern: Phoenix.HTML.inputs_for($$$)
message: Phoenix.HTML.inputs_for is deprecated. Use Phoenix.Component.inputs_for/1.
```

- [ ] **Step 4: Create rules/elixir/no-live-redirect.yml**

```yaml
id: no-live-redirect
language: elixir
severity: error
rule:
  pattern: live_redirect($$$)
message: live_redirect is deprecated. Use <.link navigate={href}> or push_navigate/2.
```

- [ ] **Step 5: Create rules/elixir/no-live-patch.yml**

```yaml
id: no-live-patch
language: elixir
severity: error
rule:
  pattern: live_patch($$$)
message: live_patch is deprecated. Use <.link patch={href}> or push_patch/2.
```

- [ ] **Step 6: Create rules/elixir/no-eex-sigil.yml**

```yaml
id: no-eex-sigil
language: elixir
severity: error
rule:
  kind: sigil
  regex: "^~E"
message: ~E sigil is deprecated. Use ~H sigils or .html.heex files.
```

- [ ] **Step 7: Verify all rules parse**

```bash
cd /home/noah/projects/readaloud && ast-grep scan --rule rules/elixir/no-phoenix-view.yml /dev/null 2>&1
```
Expected: no errors about rule parsing. Repeat for each rule file.

- [ ] **Step 8: Commit**

```bash
git add rules/elixir/no-phoenix-view.yml rules/elixir/no-form-for.yml rules/elixir/no-inputs-for.yml rules/elixir/no-live-redirect.yml rules/elixir/no-live-patch.yml rules/elixir/no-eex-sigil.yml
git commit -m "ci: add ast-grep rules for deprecated Phoenix APIs"
```

### Task 4: Remaining Elixir rules

**Files:**
- Create: `rules/elixir/no-banned-http-clients.yml`
- Create: `rules/elixir/no-heroicons-module.yml`

- [ ] **Step 1: Create rules/elixir/no-banned-http-clients.yml**

```yaml
id: no-banned-http-clients
language: elixir
severity: error
rule:
  any:
    - pattern: ":httpoison"
    - pattern: ":tesla"
    - pattern: ":httpc"
files:
  - "**/mix.exs"
message: Use Req for HTTP requests. :httpoison, :tesla, and :httpc are banned.
```

- [ ] **Step 2: Create rules/elixir/no-heroicons-module.yml**

```yaml
id: no-heroicons-module
language: elixir
severity: error
rule:
  pattern: Heroicons.$METHOD($$$)
message: Don't use Heroicons modules. Use the <.icon name="hero-x-mark" /> component.
```

- [ ] **Step 3: Run full ast-grep scan on the actual codebase**

```bash
cd /home/noah/projects/readaloud && ast-grep scan 2>&1
```
Expected: either clean (no matches) or legitimate violations that need fixing. If the codebase has existing violations, note them — they need to be fixed before the check can be gated.

- [ ] **Step 4: Commit**

```bash
git add rules/elixir/no-banned-http-clients.yml rules/elixir/no-heroicons-module.yml
git commit -m "ci: add ast-grep rules for banned HTTP clients and Heroicons"
```

---

## Chunk 2: ast-grep HEEx Rules

### Task 5: HEEx rules (HTML language mapping)

**Files:**
- Create: `rules/heex/no-raw-script-tags.yml`
- Create: `rules/heex/no-phx-update-append.yml`
- Create: `rules/heex/no-phx-update-prepend.yml`
- Create: `rules/heex/no-html-comments.yml`

- [ ] **Step 1: Create rules/heex/no-raw-script-tags.yml**

```yaml
id: no-raw-script-tags
language: html
severity: error
rule:
  kind: script_element
message: Don't use raw <script> tags in HEEx. Use colocated JS hooks with :type={Phoenix.LiveView.ColocatedHook}.
```

- [ ] **Step 2: Create rules/heex/no-phx-update-append.yml**

```yaml
id: no-phx-update-append
language: html
severity: error
rule:
  kind: attribute
  has:
    kind: attribute_name
    regex: "^phx-update$"
  all:
    - has:
        kind: quoted_attribute_value
        has:
          kind: attribute_value
          regex: "^append$"
message: phx-update="append" is deprecated. Use LiveView streams.
```

- [ ] **Step 3: Create rules/heex/no-phx-update-prepend.yml**

```yaml
id: no-phx-update-prepend
language: html
severity: error
rule:
  kind: attribute
  has:
    kind: attribute_name
    regex: "^phx-update$"
  all:
    - has:
        kind: quoted_attribute_value
        has:
          kind: attribute_value
          regex: "^prepend$"
message: phx-update="prepend" is deprecated. Use LiveView streams.
```

- [ ] **Step 4: Create rules/heex/no-html-comments.yml**

```yaml
id: no-html-comments
language: html
severity: warning
rule:
  kind: comment
message: Use HEEx comments <%!-- --%> instead of HTML <!-- --> comments.
```

- [ ] **Step 5: Test against actual .heex files**

```bash
cd /home/noah/projects/readaloud && ast-grep scan 2>&1 | grep -E "(script|phx-update|html-comments)"
```
Expected: no false positives from legitimate colocated hooks (which use `:type={Phoenix.LiveView.ColocatedHook}`, a different tree-sitter node than plain `<script>`).

- [ ] **Step 6: Commit**

```bash
git add rules/heex/
git commit -m "ci: add ast-grep HEEx rules (script tags, phx-update, HTML comments)"
```

---

## Chunk 3: Grep Companion (Nix writeShellScriptBin)

### Task 6: Create lint-grep.nix

**Files:**
- Create: `cells/app/lint-grep.nix`

- [ ] **Step 1: Create cells/app/lint-grep.nix**

This defines the grep companion linter as a Nix derivation. Both the check derivation and lefthook/devshell import this file to get the same package.

```nix
{ nixpkgs }:
let
  inherit (nixpkgs) gnugrep findutils;
in
nixpkgs.writeShellScriptBin "lint-grep" ''
  set -euo pipefail
  errors=0

  check_grep() {
    local pattern="$1" include="$2" msg="$3"
    local matches
    if matches=$(${gnugrep}/bin/grep -rn "$pattern" --include="$include" . 2>/dev/null); then
      echo "ERROR: $msg"
      echo "$matches"
      ((errors++)) || true
    fi
  }

  # Rule 16: no-flash-group-outside-layouts
  flash_matches=$(${findutils}/bin/find . -name '*.heex' ! -name '*layout*' ! -path '*/layouts/*' \
    -exec ${gnugrep}/bin/grep -ln '<\.flash_group' {} + 2>/dev/null || true)
  if [ -n "$flash_matches" ]; then
    echo "ERROR: <.flash_group> must only be used inside layouts."
    echo "$flash_matches"
    ((errors++)) || true
  fi

  # Rule 17: no-form-for-changeset
  check_grep \
    '<\.form.*for={@changeset}' \
    '*.heex' \
    'Never pass @changeset to <.form>. Use to_form/2 to create @form first.'

  # Rule 18: no-form-let
  check_grep \
    '<\.form.*let={' \
    '*.heex' \
    '<.form let={f}> is deprecated. Use <.form for={@form}> and @form[:field].'

  # Rule 19: no-enum-each-in-heex
  check_grep \
    'Enum\.each' \
    '*.heex' \
    "Don't use Enum.each in HEEx. Use for comprehension: <%= for item <- @items do %>."

  # Rule 20: no-css-apply
  check_grep \
    '@apply ' \
    '*.css' \
    "Don't use @apply in CSS. Write Tailwind classes directly on elements."

  # Rule 21: no-is-prefix-functions
  is_matches=$(${gnugrep}/bin/grep -rEn '^\s*(def|defp)\s+is_' --include='*.ex' --include='*.exs' . 2>/dev/null \
    | ${gnugrep}/bin/grep -v 'defguard' || true)
  if [ -n "$is_matches" ]; then
    echo "ERROR: Predicate functions should end with ? not start with is_. Reserve is_ for guards."
    echo "$is_matches"
    ((errors++)) || true
  fi

  # Rule 22: no-nested-modules
  while IFS= read -r file; do
    count=$(${gnugrep}/bin/grep -c '^defmodule ' "$file" 2>/dev/null || echo 0)
    if [ "$count" -gt 1 ]; then
      echo "ERROR: Multiple top-level modules in $file — causes cyclic dependencies."
      ((errors++)) || true
    fi
  done < <(${findutils}/bin/find . -name '*.ex' -not -path './_build/*' -not -path './deps/*' 2>/dev/null)

  if [ "$errors" -gt 0 ]; then
    echo ""
    echo "Found $errors grep lint error(s)."
    exit 1
  fi
''
```

- [ ] **Step 2: Test the derivation builds and runs**

```bash
cd /home/noah/projects/readaloud && nix build --expr '(import ./cells/app/lint-grep.nix { nixpkgs = import <nixpkgs> {}; })' 2>&1
```

Alternatively, test after integrating in Task 7.

- [ ] **Step 3: Commit**

```bash
git add cells/app/lint-grep.nix
git commit -m "ci: add grep companion lint checks as nix writeShellScriptBin"
```

---

## Chunk 4: Nix Integration

### Task 7: Add ast-grep check derivation

**Files:**
- Create: `cells/app/checks/ast-grep.nix`
- Modify: `cells/app/checks/default.nix`

- [ ] **Step 1: Create cells/app/checks/ast-grep.nix**

```nix
{ nixpkgs, self, lintGrep }:
nixpkgs.runCommand "ast-grep-check"
  {
    nativeBuildInputs = [
      nixpkgs.ast-grep
      lintGrep
    ];
  }
  ''
    cd ${self}
    ast-grep scan
    lint-grep
    touch $out
  ''
```

- [ ] **Step 2: Add ast-grep to checks/default.nix**

Add a `lintGrep` binding in the `let` block, and a new check entry:

```nix
{ inputs, cell }:
let
  inherit (inputs) nixpkgs self;
  l = nixpkgs.lib;
  beamPackages = nixpkgs.beam.packagesWith nixpkgs.beam.interpreters.erlang_27;

  mixFodDepsDev = beamPackages.fetchMixDeps {
    pname = "readaloud-deps-dev";
    version = "0.1.0";
    src = self;
    mixEnv = "dev";
    hash = "sha256-pP65vt/zenhrpoaec1ASh671FSNWJG5tazgXBMSCJ1c=";
  };

  treefmtData = {
    global.excludes = [
      "_build/**"
      "deps/**"
    ];
    formatter = import ../treefmt-formatters.nix { inherit nixpkgs l; };
  };

  lintGrep = import ../lint-grep.nix { inherit nixpkgs; };
in
{
  formatting = import ./formatting.nix {
    inherit
      nixpkgs
      self
      l
      treefmtData
      beamPackages
      mixFodDepsDev
      ;
  };
  statix = import ./statix.nix { inherit nixpkgs self; };
  deadnix = import ./deadnix.nix { inherit nixpkgs self; };
  biome-lint = import ./biome-lint.nix { inherit nixpkgs self; };
  ast-grep = import ./ast-grep.nix { inherit nixpkgs self lintGrep; };
  credo = import ./credo.nix {
    inherit
      nixpkgs
      self
      beamPackages
      mixFodDepsDev
      ;
  };
}
```

- [ ] **Step 3: Test the Nix check**

```bash
cd /home/noah/projects/readaloud && nix build .#checks.x86_64-linux.ast-grep 2>&1
```
Expected: builds successfully (exit 0) if codebase is clean, or fails with ast-grep/grep output if violations exist.

- [ ] **Step 4: Commit**

```bash
git add cells/app/checks/ast-grep.nix cells/app/checks/default.nix
git commit -m "ci: add ast-grep Nix check derivation"
```

### Task 8: Update lefthook and devshell

**Files:**
- Modify: `cells/app/configs.nix`
- Modify: `cells/app/devshells.nix`

- [ ] **Step 1: Add ast-grep and lint-grep to lefthook pre-commit in configs.nix**

In `cells/app/configs.nix`, add `lintGrep` to the `let` block and reference both tools in lefthook:

```nix
{ inputs, cell }:
let
  inherit (inputs) nixpkgs;
  inherit (inputs.std.lib.dev) mkNixago;
  l = nixpkgs.lib;
  lintGrep = import ./lint-grep.nix { inherit nixpkgs; };
in
{
  # ... treefmt unchanged ...

  lefthook = mkNixago {
    data = {
      pre-commit = {
        commands = {
          treefmt = {
            run = "${l.getExe nixpkgs.treefmt} --fail-on-change";
          };
          ast-grep = {
            run = "${l.getExe nixpkgs.ast-grep} scan";
          };
          lint-grep = {
            run = "${l.getExe lintGrep}";
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
    hook.extra = ''
      ${l.getExe nixpkgs.lefthook} install
    '';
  };

  # ... conform, editorconfig unchanged ...
}
```

- [ ] **Step 2: Add ast-grep and lint-grep to devshell packages in devshells.nix**

Add `lintGrep` to the `let` block and both packages to the `packages` list:

```nix
{ inputs, cell }:
let
  inherit (inputs) nixpkgs;
  # ... existing bindings ...
  lintGrep = import ./lint-grep.nix { inherit nixpkgs; };
in
{
  default = lib.dev.mkShell {
    # ...
    packages = [
      # ... existing packages ...

      # Dev tools
      nixpkgs.treefmt
      nixpkgs.nixfmt
      nixpkgs.biome
      nixpkgs.statix
      nixpkgs.deadnix
      nixpkgs.lefthook
      nixpkgs.conform
      nixpkgs.ast-grep
      lintGrep
    ];
    # ...
  };
}
```

- [ ] **Step 3: Update the lint command in devshells.nix**

Update the `lint` command to use the Nix-built binaries:

```nix
      {
        name = "lint";
        help = "Run all linters";
        command = "${l.getExe nixpkgs.statix} check . && ${l.getExe nixpkgs.deadnix} . && ${l.getExe nixpkgs.biome} lint apps/readaloud_web/assets/js/ && ${l.getExe nixpkgs.ast-grep} scan && ${l.getExe lintGrep} && mix credo --strict";
      }
```

- [ ] **Step 4: Verify the devshell enters and lefthook.yml generates**

```bash
cd /home/noah/projects/readaloud && nix develop -c lefthook run pre-commit 2>&1
```
Expected: lefthook runs treefmt, ast-grep, and lint-grep checks.

- [ ] **Step 5: Commit**

```bash
git add cells/app/configs.nix cells/app/devshells.nix
git commit -m "ci: add ast-grep to lefthook pre-commit and devshell"
```

---

## Chunk 5: Scope Down AGENTS.md

### Task 9: Remove enforced rules from AGENTS.md

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Read current AGENTS.md**

```bash
cat AGENTS.md
```

- [ ] **Step 2: Remove the following enforced rules (keeping only non-pattern-matchable content)**

Remove these specific sections/lines that are now enforced by ast-grep or grep:

**From "Project guidelines" (lines 6):**
- Remove: "avoid :httpoison, :tesla, and :httpc" clause from the Req bullet (keep the positive "Use Req" part)

**From "Phoenix v1.8 guidelines" (lines 15-16):**
- Remove: `<.flash_group>` ban (line 15) — enforced by grep
- Remove: "never use Heroicons modules" clause from line 16 (keep the positive "Always use <.icon>" part)

**From "JS and CSS guidelines" (lines 32-37):**
- Remove: "Never use @apply" (line 32) — enforced by grep
- Remove: "Never write inline <script> tags" (line 37) — enforced by ast-grep

**From "Phoenix guidelines" (line 121):**
- Remove: "Phoenix.View no longer is needed" (line 121) — enforced by ast-grep

**From "Elixir guidelines" (lines 80-84):**
- Remove: "Never nest multiple modules" (line 80) — enforced by grep
- Remove: `String.to_atom/1` warning (line 83) — enforced by ast-grep
- Remove: "Predicate function names should not start with is_" (line 84) — enforced by grep

**From "Test guidelines" (lines 97):**
- Remove: "Avoid Process.sleep/1 and Process.alive?/1" block (lines 97-103) — enforced by ast-grep

**From "Phoenix HTML guidelines" (lines 127-128, 133, 181-182):**
- Remove: "never use ~E" (line 127) — enforced by ast-grep
- Remove: "Never use Phoenix.HTML.form_for or Phoenix.HTML.inputs_for" (line 128) — enforced by ast-grep
- Remove: "Never use else if" example block (lines 133-152) — keep as teaching, but the `else if` concept can't be pattern-matched so it stays
- Remove: "Never use <% Enum.each %>" (line 181) — enforced by grep
- Remove: HTML comment syntax note (line 182) — enforced by ast-grep

**From "Phoenix LiveView guidelines" (lines 206, 279, 291):**
- Remove: "Never use live_redirect and live_patch" (line 206) — enforced by ast-grep
- Remove: "Never use phx-update='append' or phx-update='prepend'" (line 279) — enforced by ast-grep
- Remove: "Never write raw <script> tags" (line 291) — enforced by ast-grep

**From form handling (lines 426-434):**
- Remove: "Never use <.form for={@changeset}" example (lines 426-434) — enforced by grep
- Remove: "Never use <.form let={f}" (line 434) — enforced by grep

- [ ] **Step 3: Add a reference to the linting tools at the top of AGENTS.md**

Add after line 5 (`Use mix precommit alias...`):

```markdown
- Code patterns are enforced by `ast-grep scan` and `lint-grep` (run via lefthook pre-commit). See `rules/` and `cells/app/lint-grep.nix` for the full rule set. The rules below cover guidance that can't be machine-enforced.
```

- [ ] **Step 4: Verify AGENTS.md is coherent after removal**

Read through the modified file to ensure remaining content flows logically and no dangling references exist.

- [ ] **Step 5: Run all checks to verify nothing broke**

```bash
cd /home/noah/projects/readaloud && ast-grep scan && lint-grep
```
Expected: clean (no violations).

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md
git commit -m "docs: scope down AGENTS.md, rules now enforced by ast-grep/grep CI"
```

---

## Chunk 6: Fix Existing Violations & Final Verification

### Task 10: Fix any existing codebase violations

**Files:**
- Varies based on violations found

- [ ] **Step 1: Run full ast-grep scan and grep lint**

```bash
cd /home/noah/projects/readaloud && ast-grep scan 2>&1; echo "---"; lint-grep 2>&1
```

- [ ] **Step 2: Fix each violation**

For each violation found, fix the code to use the recommended alternative. If a violation is a false positive, add it to the rule's `ignoreFiles` list or adjust the pattern.

- [ ] **Step 3: Run the full Nix check suite**

```bash
cd /home/noah/projects/readaloud && nix flake check 2>&1
```
Expected: all checks pass including the new `ast-grep` check.

- [ ] **Step 4: Commit fixes**

```bash
git add -A
git commit -m "fix: resolve existing lint violations caught by new ast-grep rules"
```
