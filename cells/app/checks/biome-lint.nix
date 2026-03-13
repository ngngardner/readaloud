{ nixpkgs, self }:
nixpkgs.runCommand "biome-lint-check"
  {
    nativeBuildInputs = [ nixpkgs.biome ];
  }
  ''
    cd ${self}
    biome lint apps/readaloud_web/assets/js/
    touch $out
  ''
