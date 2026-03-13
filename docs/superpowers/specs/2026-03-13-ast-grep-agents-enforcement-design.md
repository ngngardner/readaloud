# ast-grep AGENTS.md Rule Enforcement

Replace soft AGENTS.md rules with hard CI gates via ast-grep linting.

## Approach

- ast-grep for Elixir patterns (native support)
- ast-grep with `.heex` → HTML language mapping for HEEx patterns
- Grep companion as `writeShellScriptBin` for patterns ast-grep can't handle (Phoenix function components, multi-module detection, `is_` prefix functions)
- Nix check derivation + lefthook pre-commit integration

## Project Structure

```
readaloud/
  sgconfig.yml                          # ast-grep config with languageGlobs
  rules/                               # ast-grep YAML rules
    elixir/
      no-string-to-atom.yml
      no-process-sleep-in-tests.yml
      no-process-alive-in-tests.yml
      no-phoenix-view.yml
      no-form-for.yml
      no-inputs-for.yml
      no-live-redirect.yml
      no-live-patch.yml
      no-eex-sigil.yml
      no-banned-http-clients.yml
      no-heroicons-module.yml
    heex/
      no-raw-script-tags.yml
      no-phx-update-append.yml
      no-phx-update-prepend.yml
      no-html-comments.yml
  cells/app/lint-grep.nix              # Grep companion (writeShellScriptBin)
  cells/app/checks/ast-grep.nix        # Nix check derivation
  cells/app/configs.nix                 # Updated lefthook config
```

## ast-grep Rules

### Elixir Rules

#### 1. no-string-to-atom
- **Pattern**: `String.to_atom($A)`
- **Severity**: warning
- **Message**: Avoid String.to_atom/1 — memory leak risk with dynamic input. Use String.to_existing_atom/1 or explicit mapping.
- **Files**: `**/*.{ex,exs}`

#### 2. no-process-sleep-in-tests
- **Pattern**: `Process.sleep($A)`
- **Severity**: error
- **Message**: Don't use Process.sleep/1 in tests. Use Process.monitor/1 + assert_receive or :sys.get_state/1 for synchronization.
- **Files**: `test/**/*.exs`

#### 3. no-process-alive-in-tests
- **Pattern**: `Process.alive?($A)`
- **Severity**: error
- **Message**: Don't use Process.alive?/1 in tests. Use Process.monitor/1 + assert_receive {:DOWN, ...}.
- **Files**: `test/**/*.exs`

#### 4. no-phoenix-view
- **Pattern**: `use Phoenix.View`
- **Severity**: error
- **Message**: Phoenix.View is removed. Use Phoenix.Component and ~H sigils.

#### 5. no-form-for
- **Pattern**: `Phoenix.HTML.form_for($$$)`
- **Severity**: error
- **Message**: Phoenix.HTML.form_for is deprecated. Use to_form/2 + <.form for={@form}>.

#### 6. no-inputs-for
- **Pattern**: `Phoenix.HTML.inputs_for($$$)`
- **Severity**: error
- **Message**: Phoenix.HTML.inputs_for is deprecated. Use Phoenix.Component.inputs_for/1.

#### 7. no-live-redirect
- **Pattern**: `live_redirect($$$)`
- **Severity**: error
- **Message**: live_redirect is deprecated. Use <.link navigate={href}> or push_navigate/2.

#### 8. no-live-patch
- **Pattern**: `live_patch($$$)`
- **Severity**: error
- **Message**: live_patch is deprecated. Use <.link patch={href}> or push_patch/2.

#### 9. no-eex-sigil
- **Pattern**: `~E`
- **Severity**: error
- **Message**: ~E sigil is deprecated. Use ~H sigils or .html.heex files.

#### 10. no-banned-http-clients
- **Patterns**: `:httpoison`, `:tesla`, `:httpc`
- **Severity**: error
- **Message**: Use Req for HTTP requests. :httpoison, :tesla, and :httpc are banned.
- **Files**: `**/mix.exs`

#### 11. no-heroicons-module
- **Pattern**: `Heroicons.$METHOD($$$)`
- **Severity**: error
- **Message**: Don't use Heroicons modules. Use the <.icon name="hero-x-mark" /> component.

### HEEx Rules (HTML language mapping)

#### 12. no-raw-script-tags
- **Pattern**: `<script>$$$</script>` (HTML)
- **Severity**: error
- **Message**: Don't use raw <script> tags in HEEx. Use colocated JS hooks with :type={Phoenix.LiveView.ColocatedHook}.
- **Files**: `**/*.heex`

#### 13. no-phx-update-append
- **Rule type**: YAML rule with `kind: attribute` + `has` combinator matching attribute name `phx-update` and value `append`
- **Severity**: error
- **Message**: phx-update="append" is deprecated. Use LiveView streams.

#### 14. no-phx-update-prepend
- **Rule type**: YAML rule with `kind: attribute` + `has` combinator matching attribute name `phx-update` and value `prepend`
- **Severity**: error
- **Message**: phx-update="prepend" is deprecated. Use LiveView streams.

#### 15. no-html-comments
- **Rule type**: YAML rule with `kind: comment`
- **Severity**: warning
- **Message**: Use HEEx comments <%!-- --%> instead of HTML <!-- --> comments in .heex files.

### Grep Companion Rules (`scripts/lint-grep.sh`)

These patterns either involve Phoenix function components (`.` prefix syntax not parseable by HTML tree-sitter) or require cross-node analysis that ast-grep can't handle.

#### 16. no-flash-group-outside-layouts
- **Grep**: `<\.flash_group` in `**/*.heex` excluding `**/layouts*`
- **Message**: <.flash_group> must only be used inside layouts.ex.

#### 17. no-form-for-changeset
- **Grep**: `<\.form.*for=\{@changeset\}` in `**/*.heex`
- **Message**: Never pass @changeset to <.form>. Use to_form/2 to create @form first.

#### 18. no-form-let
- **Grep**: `<\.form.*let=\{` in `**/*.heex`
- **Message**: <.form let={f}> is deprecated. Use <.form for={@form}> and @form[:field].

#### 19. no-enum-each-in-heex
- **Grep**: `Enum\.each` in `**/*.heex`
- **Message**: Don't use Enum.each in HEEx. Use for comprehension: <%= for item <- @items do %>.

#### 20. no-css-apply
- **Grep**: `@apply\s` in `**/*.css`
- **Message**: Don't use @apply in CSS. Write Tailwind classes directly on elements.

#### 21. no-is-prefix-functions
- **Grep**: `^\s*(def|defp)\s+is_` in `**/*.{ex,exs}`, excluding lines with `defguard`
- **Message**: Elixir predicate functions should end with ? not start with is_. Reserve is_ for guards.

#### 22. no-nested-modules
- **Grep**: Files with more than one `^defmodule ` line (not indented)
- **Message**: Don't define multiple modules in the same file — causes cyclic dependencies.

## Nix Integration

### Grep Companion (`cells/app/lint-grep.nix`)

Defined as `writeShellScriptBin "lint-grep"` with fully qualified store paths for `grep` and `find`. Imported by both `checks/default.nix` and `configs.nix`.

### Check Derivation (`cells/app/checks/ast-grep.nix`)

Read-only check — no source copy needed (matches `statix.nix`/`deadnix.nix` pattern):

```nix
{ nixpkgs, self, lintGrep }:
nixpkgs.runCommand "ast-grep-check"
  {
    nativeBuildInputs = [ nixpkgs.ast-grep lintGrep ];
  }
  ''
    cd ${self}
    ast-grep scan
    lint-grep
    touch $out
  ''
```

### Lefthook Update (`cells/app/configs.nix`)

Add `ast-grep` and `lint-grep` commands to the existing `pre-commit` hook:

```nix
let
  lintGrep = import ./lint-grep.nix { inherit nixpkgs; };
in
# ...
pre-commit.commands.ast-grep.run = "${l.getExe nixpkgs.ast-grep} scan";
pre-commit.commands.lint-grep.run = "${l.getExe lintGrep}";
```

## AGENTS.md Scoping

Remove all 22 rules above from AGENTS.md. The remaining content covers:
- Process guidance (use `mix precommit`, mix task docs)
- Positive patterns (use `<Layouts.app>`, `<.icon>`, `<.input>`, `to_form`)
- Teaching (streams API, form handling, push events, router scopes)
- Type-dependent rules (list access, struct access, changeset access)
- Subjective guidelines (UI/UX design, test strategy)
