# Vendored from divnix/std (Unlicense): src/lib/dev/mkShell.nix and
# src/lib/dev/mkNixago.nix. This is the ~10% of std this repo actually
# used — the devshell wrapper that wires nixago "pebbles" into shell
# startup hooks. devshell/nixago come from this flake's direct inputs;
# dmerge.merge is replaced by lib.recursiveUpdate (this repo only ever
# merges plain attrsets, no array-merge markers).
#
# Returns a per-system attrset; grow.nix's deSystemize folds the current
# system up, so cells use `inputs.vendor.mkShell` / `inputs.vendor.mkNixago`.
{ inputs, systems }:
let
  l = inputs.nixpkgs.lib // builtins;

  forSystem =
    system:
    let
      devshell = inputs.devshell.legacyPackages.${system};
      nixago = inputs.nixago.lib.${system};

      # devshell module that wires `nixago = [ ... ]` pebbles into
      # startup hooks, and excludes generated files from treefmt
      nixagoModule =
        {
          config,
          lib,
          ...
        }:
        with lib;
        let
          cfg = config;
        in
        {
          options.nixago = mkOption {
            type = types.listOf types.attrs;
            default = [ ];
            apply = x: l.catAttrs "__passthru" x;
            description = "List of Nixago pebbles to load";
          };

          config =
            let
              # prevent treefmt from formatting auto-generated files
              partitioned = l.partition (n: n.output == "treefmt.toml") cfg.nixago;
              treefmt' = l.map (
                t:
                l.recursiveUpdate t {
                  data.global.excludes = t.data.global.excludes or [ ] ++ (l.map (o: o.output) cfg.nixago);
                }
              ) partitioned.right;
              updated = treefmt' ++ partitioned.wrong;
            in
            mkIf (cfg.nixago != [ ]) {
              devshell =
                let
                  acc = l.foldl l.recursiveUpdate { };
                in
                acc (
                  (l.map (o: o.devshell) updated)
                  ++ [
                    { startup.nixago-setup-hook = l.stringsWithDeps.noDepEntry (nixago.makeAll updated).shellHook; }
                  ]
                );
              packages = l.concatMap (o: o.packages) updated;
              commands = l.concatMap (o: o.commands) updated;
            };
        };

      mkShell =
        configuration:
        devshell.mkShell {
          imports = [
            configuration
            nixagoModule
          ];
        };

      mkNixago =
        configuration:
        let
          # implement a minimal numtide/devshell forward contract
          configuration' = configuration // {
            hook = configuration.hook or { };
            packages = configuration.packages or [ ];
            commands = configuration.commands or [ ];
            devshell = configuration.devshell or { };
          };
          # transparently extend config data with a functor
          __functor =
            self:
            {
              data ? { },
              hook ? { },
              packages ? [ ],
              commands ? [ ],
              devshell ? { },
              output ? null,
            }:
            let
              __passthru = self.__passthru or configuration';
              newSelf = __passthru // {
                data = l.recursiveUpdate __passthru.data data;
                hook = l.recursiveUpdate __passthru.hook hook;
                packages = __passthru.packages ++ packages;
                commands = __passthru.commands ++ commands;
                devshell = l.recursiveUpdate __passthru.devshell devshell;
                output = if output != null then output else __passthru.output;
              };
            in
            (nixago.make newSelf)
            // {
              # keep here, cause nixago.make would strip them
              inherit __functor;
              __passthru = newSelf;
            };
        in
        __functor configuration' { };
    in
    {
      inherit mkShell mkNixago;
    };
in
l.genAttrs systems forSystem
