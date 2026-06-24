{
  description = "ReadAloud — audiobook generation and reading companion";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # devshell pinned to the rev the old divnix/hive input locked, so the
    # vendored mkShell behaves identically; bump freely later.
    devshell = {
      url = "github:numtide/devshell/f6aec2e8b1cdddcab10ce7fc2eac66886e3deaad";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixago = {
      url = "github:nix-community/nixago";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      systems = [ "x86_64-linux" ];
      vlib = import ./nix/lib { inherit inputs systems; };
      eachSystem = nixpkgs.lib.genAttrs systems;

      # Single-cell flake: cells/app/{devshells,packages,configs,checks,
      # nixosModules}. grow loads each block into the `app` cell fixpoint
      # and injects the per-system mkShell/mkNixago via `inputs.vendor`.
      grown = vlib.grow {
        inputs = inputs // {
          inherit (vlib) vendor;
        };
        cellsFrom = ./cells;
        cellBlocks = [
          "devshells"
          "packages"
          "configs"
          "checks"
          "nixosModules"
        ];
        inherit systems;
      };
    in
    {
      devShells = eachSystem (system: grown.${system}.app.devshells or { });
      packages = eachSystem (system: grown.${system}.app.packages or { });
      checks = eachSystem (system: grown.${system}.app.checks or { });
      # NixOS modules are system-independent functions.
      nixosModules = grown.x86_64-linux.app.nixosModules;
    };
}
