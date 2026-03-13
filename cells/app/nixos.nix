# This file is imported directly by flake.nix, not through std blocks.
# NixOS modules are system-independent and cannot go through std's per-system evaluation.
{ package }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.readaloud;
in
{
  options.services.readaloud = {
    enable = lib.mkEnableOption "ReadAloud audiobook service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
      description = "Port for the Phoenix web server";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "Hostname for the Phoenix web server (PHX_HOST)";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/readaloud";
      description = "Directory for persistent data (database, generated audio)";
    };

    localaiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:8080";
      description = "URL of the LocalAI service for TTS/STT";
    };

    secretKeyBaseFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the Phoenix SECRET_KEY_BASE";
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
        PHX_HOST = cfg.host;
        PORT = toString cfg.port;
        LOCALAI_URL = cfg.localaiUrl;
        RELEASE_TMP = "/tmp/readaloud";
        PATH = lib.makeBinPath (
          with pkgs;
          [
            calibre
            poppler-utils
          ]
        );
      };

      serviceConfig = {
        Type = "exec";
        User = "readaloud";
        Group = "readaloud";
        StateDirectory = "readaloud";
        RuntimeDirectory = "readaloud";
        WorkingDirectory = cfg.dataDir;

        ExecStartPre = "${package}/bin/readaloud eval 'ReadaloudLibrary.Release.migrate()'";
        ExecStop = "${package}/bin/readaloud stop";
        Restart = "on-failure";
        RestartSec = 5;

        # Read secret key from file
        LoadCredential = "secret_key_base:${cfg.secretKeyBaseFile}";

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfg.dataDir ];
      };

      # Inject SECRET_KEY_BASE from credential file, then exec the release
      script = ''
        export SECRET_KEY_BASE="$(cat $CREDENTIALS_DIRECTORY/secret_key_base)"
        exec ${package}/bin/readaloud start
      '';
    };
  };
}
