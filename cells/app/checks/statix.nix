{ nixpkgs, self }:
nixpkgs.runCommand "statix-check"
  {
    nativeBuildInputs = [ nixpkgs.statix ];
  }
  ''
    cd ${self}
    statix check .
    touch $out
  ''
