{ inputs, cell }:
let
  inherit (inputs) nixpkgs;
  inherit (inputs.std.lib.dev) mkNixago;
  l = nixpkgs.lib;
in
{
  treefmt = mkNixago {
    data = {
      formatter = import ./treefmt-formatters.nix { inherit nixpkgs l; };
    };
    output = "treefmt.toml";
    format = "toml";
  };

  lefthook = mkNixago {
    data = {
      pre-commit = {
        commands = {
          treefmt = {
            run = "${l.getExe nixpkgs.treefmt} --fail-on-change";
          };
        };
      };
      commit-msg = {
        commands = {
          conform = {
            run = "${l.getExe nixpkgs.conform} enforce --commit-msg-file {1}";
          };
        };
      };
    };
    output = "lefthook.yml";
    format = "yaml";
    hook.extra = ''
      ${l.getExe nixpkgs.lefthook} install
    '';
  };

  conform = mkNixago {
    data = {
      policies = [
        {
          type = "commit";
          spec = {
            header = {
              length = 72;
              imperative = true;
              case = "lower";
              invalidLastCharacters = ".";
            };
            body.required = false;
            conventional = {
              types = [
                "feat"
                "fix"
                "chore"
                "docs"
                "refactor"
                "test"
                "ci"
                "style"
                "perf"
              ];
              scopes = [ ".*" ];
            };
          };
        }
      ];
    };
    output = ".conform.yaml";
    format = "yaml";
  };

  editorconfig = mkNixago {
    data = {
      root = true;
      "*" = {
        end_of_line = "lf";
        insert_final_newline = true;
        trim_trailing_whitespace = true;
        charset = "utf-8";
      };
      "*.{nix,ex,exs,js,css,heex}" = {
        indent_style = "space";
        indent_size = 2;
      };
    };
    output = ".editorconfig";
    engine =
      request:
      let
        inherit (request) data output;
        name = nixpkgs.lib.baseNameOf output;
        value = {
          globalSection = {
            root = data.root or true;
          };
          sections = nixpkgs.lib.removeAttrs data [ "root" ];
        };
      in
      nixpkgs.writeText name (nixpkgs.lib.generators.toINIWithGlobalSection { } value);
  };
}
