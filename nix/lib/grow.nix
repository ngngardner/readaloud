# Vendored from paisano-nix/core grow/ (Unlicense), trimmed to what this
# repo uses: no __std TUI registry, no actions, no yants type checks, no
# per-cell flake.nix support.
#
# Crucially, block paths are built by *path append*
# (cellsFrom + "/cell/block.nix") rather than string interpolation
# ("${cellsFrom}/..."), so no rootless store copy of ./cells is ever
# created — that copy was the source of the recurring
# "path '/nix/store/…-incl' is not valid" flake-check failures that the
# old divnix/hive + std + paisano stack produced.
{ lib }:
let
  l = lib // builtins;
  deSystemize = import ./desystemize.nix;
in
{
  inputs, # flake inputs (plus any extra attrs flake.nix injects, e.g. `vendor`)
  cellsFrom, # path value, e.g. ./cells
  cellBlocks, # list of block names (strings); <cell>/<name>.nix wins over <cell>/<name>/default.nix
  systems,
}:
let
  self = inputs.self.sourceInfo // {
    rev = inputs.self.sourceInfo.rev or "not-a-commit";
  };

  cellNames = l.attrNames (l.filterAttrs (_: type: type == "directory") (l.readDir cellsFrom));

  # Mimic paisano: `inputs.nixpkgs` inside a cell is an *instantiated*
  # package set for the current system that still carries
  # outPath/sourceInfo (so `import inputs.nixpkgs { }` and
  # `inputs.nixpkgs.lib` both work), with every other system reachable
  # as `inputs.nixpkgs.<system>`.
  nixpkgsFor =
    system:
    inputs.nixpkgs.legacyPackages.${system}
    // {
      inherit (inputs.nixpkgs) outPath sourceInfo;
    };

  signatureFor = system: cellName: {
    cell = grown.${system}.${cellName};
    inputs = (deSystemize system inputs) // {
      inherit self;
      cells = deSystemize system grown;
      nixpkgs =
        (nixpkgsFor system) // l.mapAttrs (system': _: nixpkgsFor system') inputs.nixpkgs.legacyPackages;
    };
  };

  loadBlock =
    signature: path:
    let
      imported = import path;
    in
    if l.isFunction imported then imported signature else imported;

  grown = l.genAttrs systems (
    system:
    l.genAttrs cellNames (
      cellName:
      let
        signature = signatureFor system cellName;
        present =
          block:
          l.filter l.pathExists [
            (cellsFrom + "/${cellName}/${block}.nix")
            (cellsFrom + "/${cellName}/${block}/default.nix")
          ];
      in
      l.foldl' (
        acc: block:
        let
          found = present block;
        in
        if found == [ ] then acc else acc // { ${block} = loadBlock signature (l.head found); }
      ) { } cellBlocks
    )
  );
in
grown
