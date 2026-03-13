{ inputs, cell }:
let
  inherit (inputs) nixpkgs;
  inherit (inputs.std) lib;
  inherit (inputs) std;
  l = nixpkgs.lib;
  beamPackages = nixpkgs.beam.packagesWith nixpkgs.beam.interpreters.erlang_27;
  lintGrep = import ./lint-grep.nix { inherit nixpkgs; };
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
      nixpkgs.ast-grep
      lintGrep
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
        command = "${l.getExe nixpkgs.ast-grep} scan && ${l.getExe lintGrep} && ${l.getExe nixpkgs.statix} check . && ${l.getExe nixpkgs.deadnix} . && ${l.getExe nixpkgs.biome} lint apps/readaloud_web/assets/js/ && mix credo --strict";
      }
      {
        name = "check";
        help = "Run nix flake check";
        command = "nix flake check";
      }
    ];
  };
}
