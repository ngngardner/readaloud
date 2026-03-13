{
  description = "ReadAloud — audiobook generation and reading companion";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    hive = {
      url = "github:divnix/hive";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std.follows = "hive/std";
  };

  outputs =
    {
      self,
      std,
      nixpkgs,
      hive,
    }@inputs:
    hive.growOn
      {
        inherit inputs;
        systems = [ "x86_64-linux" ];
        cellsFrom = ./cells;
        cellBlocks = with std.blockTypes; [
          (devshells "devshells")
          (installables "packages")
          (nixago "configs")
          (anything "checks")
          (functions "nixosModules")
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
        checks = std.harvest self [
          "app"
          "checks"
        ];
        nixosModules = std.pick self [
          "app"
          "nixosModules"
        ];
      };
}
