{ inputs, cell }:
let
  inherit (inputs) nixpkgs self;
  l = nixpkgs.lib;
  beamPackages = nixpkgs.beam.packagesWith nixpkgs.beam.interpreters.erlang_27;

  # Dev deps for checks (formatting, credo).
  # fetchMixDeps gets source directories; --no-deps-check in each check
  # bypasses the heroicons git lock mismatch in the sandbox.
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
