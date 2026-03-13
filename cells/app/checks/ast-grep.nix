{ nixpkgs, self, lintGrep }:
nixpkgs.runCommand "ast-grep-check"
  {
    nativeBuildInputs = [
      nixpkgs.ast-grep
      lintGrep
    ];
  }
  ''
    cd ${self}
    ast-grep scan
    lint-grep
    touch $out
  ''
