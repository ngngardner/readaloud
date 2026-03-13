{
  inputs,
  cell,
}:
let
  inherit (inputs) nixpkgs;
  inherit (inputs.std) lib;
  inherit (inputs) std;

  l = nixpkgs.lib;

  # Keep in sync with treefmt-nix evalModule in flake.nix
  treefmtConfig = {
    data = {
      formatter = {
        nixfmt = {
          command = l.getExe nixpkgs.nixfmt;
          includes = [ "*.nix" ];
        };
        biome = {
          command = l.getExe nixpkgs.biome;
          options = [
            "format"
            "--write"
          ];
          includes = [
            "*.js"
          ];
        };
        mix-format = {
          command = "mix";
          options = [ "format" ];
          includes = [
            "*.ex"
            "*.exs"
          ];
        };
        eclint = {
          command = l.getExe nixpkgs.eclint;
          options = [ "-fix" ];
          includes = [
            "*.nix"
            "*.ex"
            "*.exs"
            "*.js"
            "*.css"
            "*.heex"
            "*.md"
            "*.yml"
            "*.yaml"
            "*.json"
          ];
        };
      };
    };
    output = "treefmt.toml";
    format = "toml";
  };

  lefthookConfig = {
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
    hook.extra = _: ''
      ${l.getExe nixpkgs.lefthook} install
    '';
  };

  conformConfig = {
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
            body = {
              required = false;
            };
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

  editorconfigConfig = {
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
        name = l.baseNameOf output;
        value = {
          globalSection = {
            root = data.root or true;
          };
          sections = l.removeAttrs data [ "root" ];
        };
      in
      nixpkgs.writeText name (l.generators.toINIWithGlobalSection { } value);
  };
in
{
  default = lib.dev.mkShell {
    name = "readaloud-dev";

    imports = [
      std.std.devshellProfiles.default
    ];

    nixago = [
      (lib.dev.mkNixago treefmtConfig)
      (lib.dev.mkNixago lefthookConfig)
      (lib.dev.mkNixago conformConfig)
      (lib.dev.mkNixago editorconfigConfig)
    ];

    packages = with nixpkgs; [
      # Existing deps
      elixir_1_17
      erlang_27
      nodejs_22
      sqlite
      calibre
      poppler-utils
      inotify-tools

      # Formatting and linting
      treefmt
      nixfmt
      biome
      eclint
      statix
      deadnix

      # Git hooks
      lefthook
      conform
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
      {
        name = "fmt";
        help = "Format all code";
        command = "${l.getExe nixpkgs.treefmt}";
      }
      {
        name = "lint";
        help = "Run all linters";
        command = "${l.getExe nixpkgs.statix} check . && ${l.getExe nixpkgs.deadnix} . && ${l.getExe nixpkgs.biome} lint apps/readaloud_web/assets/js/ apps/readaloud_web/assets/css/";
      }
      {
        name = "check";
        help = "Run nix flake check";
        command = "nix flake check";
      }
    ];
  };
}
