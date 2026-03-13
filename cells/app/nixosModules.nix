{ inputs, cell }:
{
  readaloud =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.readaloud;
      package = cell.packages.default;
    in
    {
      options.services.readaloud = {
        enable = lib.mkEnableOption "ReadAloud audiobook service";
        port = lib.mkOption {
          type = lib.types.port;
          default = 4000;
          description = "Phoenix web server port";
        };
        host = lib.mkOption {
          type = lib.types.str;
          default = "localhost";
          description = "PHX_HOST hostname";
        };
        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/readaloud";
          description = "Persistent data directory";
        };
        localaiUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://localhost:8080";
          description = "LocalAI service URL";
        };
        secretKeyBaseFile = lib.mkOption {
          type = lib.types.path;
          description = "File containing SECRET_KEY_BASE";
        };
      };

      config = lib.mkIf cfg.enable {
        users.users.readaloud = {
          isSystemUser = true;
          group = "readaloud";
          home = cfg.dataDir;
        };
        users.groups.readaloud = { };

        systemd.services.readaloud = {
          description = "ReadAloud Audiobook Service";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];

          environment = {
            DATABASE_PATH = "${cfg.dataDir}/readaloud.db";
            STORAGE_PATH = "${cfg.dataDir}/files";
            PHX_HOST = cfg.host;
            PORT = toString cfg.port;
            LOCALAI_URL = cfg.localaiUrl;
            RELEASE_TMP = "/tmp/readaloud";
            RELEASE_COOKIE = "readaloud";
            ELIXIR_ERL_OPTIONS = "+fnu";
            PHX_CHECK_ORIGIN = "false";
          };

          path = with pkgs; [
            calibre
            poppler-utils
          ];

          serviceConfig = {
            Type = "exec";
            User = "readaloud";
            Group = "readaloud";
            StateDirectory = "readaloud";
            RuntimeDirectory = "readaloud";
            WorkingDirectory = cfg.dataDir;
            ExecStop = "${package}/bin/readaloud stop";
            Restart = "on-failure";
            RestartSec = 5;
            LoadCredential = "secret_key_base:${cfg.secretKeyBaseFile}";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            ReadWritePaths = [ cfg.dataDir ];
          };

          script = ''
            export SECRET_KEY_BASE="$(cat $CREDENTIALS_DIRECTORY/secret_key_base)"
            ${package}/bin/readaloud eval 'ReadaloudLibrary.Release.migrate()'
            exec ${package}/bin/readaloud start
          '';
        };
      };
    };
}
