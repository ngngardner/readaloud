{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            elixir_1_17
            erlang_27
            nodejs_22
            sqlite
            calibre
            poppler-utils
            inotify-tools
          ];

          shellHook = ''
            export MIX_HOME="$PWD/.mix"
            export HEX_HOME="$PWD/.hex"
            mkdir -p "$MIX_HOME" "$HEX_HOME"
          '';
        };
      });
}
