{ nixpkgs, self }:
nixpkgs.runCommand "ast-grep-check"
  {
    nativeBuildInputs = [
      nixpkgs.ast-grep
    ];
  }
  ''
    cd ${self}
    ast-grep scan
    touch $out
  ''
