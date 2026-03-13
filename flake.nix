{
  description = "ReadAloud — audiobook generation and reading companion";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    std = {
      url = "github:divnix/std";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        devshell.url = "github:numtide/devshell";
        nixago.url = "github:nix-community/nixago";
      };
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      std,
      nixpkgs,
      treefmt-nix,
      ...
    }@inputs:
    let
      systems = [ "x86_64-linux" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      # CI-safe subset of formatting checks (nix only).
      # Full formatting (biome, eclint, mix format) runs via nixago treefmt in the devshell.
      treefmtEval = eachSystem (
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );
    in
    std.growOn
      {
        inherit inputs;
        cellsFrom = ./cells;
        cellBlocks = with std.blockTypes; [
          (devshells "devshells")
          (installables "packages")
        ];
      }
      {
        devShells = std.harvest self [
          "app"
          "devshells"
        ];
        packages = std.harvest self [
          "app"
          "packages"
        ];
        nixosModules.readaloud = import ./cells/app/nixos.nix {
          package = self.packages.x86_64-linux.default;
        };
        formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);
        checks = eachSystem (pkgs: {
          formatting = treefmtEval.${pkgs.system}.config.build.check self;
          statix = pkgs.runCommand "statix-check" { nativeBuildInputs = [ pkgs.statix ]; } ''
            cd ${self}
            statix check .
            touch $out
          '';
          deadnix = pkgs.runCommand "deadnix-check" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
            cd ${self}
            deadnix --fail -L .
            touch $out
          '';
          biome-lint = pkgs.runCommand "biome-lint-check" { nativeBuildInputs = [ pkgs.biome ]; } ''
            cd ${self}
            biome lint apps/readaloud_web/assets/js/
            touch $out
          '';
        });
      };
}
