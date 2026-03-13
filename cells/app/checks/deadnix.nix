{ nixpkgs, self }:
nixpkgs.runCommand "deadnix-check"
  {
    nativeBuildInputs = [ nixpkgs.deadnix ];
  }
  ''
    cd ${self}
    deadnix --fail -L .
    touch $out
  ''
