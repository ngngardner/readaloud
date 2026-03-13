{
  inputs,
  cell,
}:
let
  inherit (inputs) nixpkgs;
  inherit (inputs.std) lib;
  std = inputs.std;
in
{
  default = lib.dev.mkShell {
    name = "readaloud-dev";

    imports = [
      std.std.devshellProfiles.default
    ];

    packages = with nixpkgs; [
      elixir_1_17
      erlang_27
      nodejs_22
      sqlite
      calibre
      poppler-utils
      inotify-tools
    ];

    env = [
      {
        name = "MIX_HOME";
        eval = "$PWD/.mix";
      }
      {
        name = "HEX_HOME";
        eval = "$PWD/.hex";
      }
      {
        name = "MIX_ENV";
        value = "dev";
      }
    ];

    commands = [
      {
        name = "setup";
        help = "Bootstrap Hex and Rebar";
        command = "mix local.hex --if-missing && mix local.rebar --if-missing";
      }
    ];
  };
}
