{ config, lib, ... }:
let
  service = "plausible";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable ${service}";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "${service}.${homelab.baseDomain}";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/${service}";
    };
    clickhouseDataDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/${service}/clickhouse";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8019;
    };
    clickhouseHttpPort = lib.mkOption {
      type = lib.types.port;
      default = 8124;
    };
    secretKeybaseFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a file containing 64 hex characters (openssl rand -hex 32)";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Plausible";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Privacy-friendly web analytics";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "plausible.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${service} = {};
    users.users.${service} = {
      group = service;
      home = cfg.dataDir;
      isSystemUser = true;
    };

    services.${service} = {
      enable = true;
      server = {
        baseUrl = "https://${cfg.url}";
        port = cfg.port;
        secretKeybaseFile = cfg.secretKeybaseFile;
      };
      database.clickhouse.url = "http://127.0.0.1:${toString cfg.clickhouseHttpPort}/default";
    };

    services.clickhouse.serverConfig = {
      http_port = cfg.clickhouseHttpPort;
      path = "${cfg.clickhouseDataDir}/";
      tmp_path = "${cfg.clickhouseDataDir}/tmp/";
      user_files_path = "${cfg.clickhouseDataDir}/user_files/";
      format_schema_path = "${cfg.clickhouseDataDir}/format_schemas/";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0751 ${service} ${service} - -"
      "d ${cfg.dataDir}/elixir_tzdata 0750 ${service} ${service} - -"
      "d ${cfg.dataDir}/tmp 0750 ${service} ${service} - -"
      "d ${cfg.clickhouseDataDir} 0700 clickhouse clickhouse - -"
    ];

    systemd.services.${service} = {
      startLimitIntervalSec = 120;
      startLimitBurst = 5;
      environment = {
        STORAGE_DIR = lib.mkForce "${cfg.dataDir}/elixir_tzdata";
        RELEASE_TMP = lib.mkForce "${cfg.dataDir}/tmp";
        HOME = lib.mkForce cfg.dataDir;
      };
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = service;
        Group = service;
        StateDirectory = lib.mkForce [ ];
        WorkingDirectory = lib.mkForce cfg.dataDir;
        ReadWritePaths = [ cfg.dataDir ];
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:${toString cfg.port}
      '';
    };

    environment.persistence."/".directories = [
      {
        directory = cfg.dataDir;
        user = service;
        group = service;
        mode = "0751";
      }
      {
        directory = cfg.clickhouseDataDir;
        user = "clickhouse";
        group = "clickhouse";
        mode = "0700";
      }
    ];
  };
}
