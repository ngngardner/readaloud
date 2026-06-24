# Vendored verbatim from divnix/nosys desys.nix (Unlicense).
# Folds the per-system level of a flake input up one level, so cells can
# write `inputs.devshell.mkShell` as well as
# `inputs.devshell.legacyPackages.${system}.mkShell`.
let
  l = builtins;
  deSystemize =
    let
      iteration =
        cutoff: system: fragment:
        if !(l.isAttrs fragment) || cutoff == 0 then
          fragment
        else
          let
            recursed = l.mapAttrs (_: iteration (cutoff - 1) system) fragment;
          in
          if l.hasAttr "${system}" fragment then
            if l.isFunction fragment.${system} then
              recursed // { __functor = _: fragment.${system}; }
            else
              recursed // fragment.${system}
          else
            recursed;
    in
    iteration 3;
in
deSystemize
