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
    if matches=$(${gnugrep}/bin/grep -rn "$pattern" --include="$include" --exclude-dir=deps --exclude-dir=_build --exclude-dir=node_modules . 2>/dev/null); then
      echo "ERROR: $msg"
      echo "$matches"
      ((errors++)) || true
    fi
  }

  # no-flash-group-outside-layouts
  flash_matches=$(${findutils}/bin/find . -name '*.heex' ! -name '*layout*' ! -path '*/layouts/*' ! -path '*/deps/*' ! -path '*/_build/*' \
    -exec ${gnugrep}/bin/grep -ln '<\.flash_group' {} + 2>/dev/null || true)
  if [ -n "$flash_matches" ]; then
    echo "ERROR: <.flash_group> must only be used inside layouts."
    echo "$flash_matches"
    ((errors++)) || true
  fi

  # no-form-for-changeset
  check_grep \
    '<\.form.*for={@changeset}' \
    '*.heex' \
    'Never pass @changeset to <.form>. Use to_form/2 to create @form first.'

  # no-form-let
  check_grep \
    '<\.form.*let={' \
    '*.heex' \
    '<.form let={f}> is deprecated. Use <.form for={@form}> and @form[:field].'

  # no-enum-each-in-heex
  check_grep \
    'Enum\.each' \
    '*.heex' \
    "Don't use Enum.each in HEEx. Use for comprehension: <%= for item <- @items do %>."

  # no-css-apply
  check_grep \
    '@apply ' \
    '*.css' \
    "Don't use @apply in CSS. Write Tailwind classes directly on elements."

  # no-is-prefix-functions
  is_matches=$(${gnugrep}/bin/grep -rEn '^\s*(def|defp)\s+is_' --include='*.ex' --include='*.exs' --exclude-dir=deps --exclude-dir=_build . 2>/dev/null \
    | ${gnugrep}/bin/grep -v 'defguard' || true)
  if [ -n "$is_matches" ]; then
    echo "ERROR: Predicate functions should end with ? not start with is_. Reserve is_ for guards."
    echo "$is_matches"
    ((errors++)) || true
  fi

  # no-nested-modules
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
