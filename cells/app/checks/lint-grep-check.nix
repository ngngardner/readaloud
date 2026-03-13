{
  nixpkgs,
  self,
  lintGrep,
}:
nixpkgs.runCommand "lint-grep-check"
  {
    nativeBuildInputs = [
      lintGrep
    ];
  }
  ''
    cd ${self}
    lint-grep
    touch $out
  ''
