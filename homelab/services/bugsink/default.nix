{ config, lib, ... }:
let
  service = "bugsink";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable ${service}";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/${service}";
    };
    uid = lib.mkOption {
      type = lib.types.int;
      default = 14237;
      description = "Host UID matching the bugsink user inside the container image.";
    };
    gid = lib.mkOption {
      type = lib.types.int;
      default = 14237;
      description = "Host GID matching the bugsink group inside the container image.";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "${service}.${homelab.baseDomain}";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8025;
    };
    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a file containing SECRET_KEY=... (and optionally CREATE_SUPERUSER=user:pass on first boot)";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Bugsink";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Self-hosted error tracking";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "sh-bugsink.png";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${service}.gid = cfg.gid;
    users.users.${service} = {
      uid = cfg.uid;
      group = service;
      isSystemUser = true;
    };

    virtualisation = {
      podman.enable = true;
      oci-containers.containers.${service} = {
        image = "bugsink/bugsink:latest";
        autoStart = true;
        extraOptions = [ "--pull=newer" ];
        volumes = [
          "${cfg.dataDir}:/data"
        ];
        environment = {
          TZ = homelab.timeZone;
          BASE_URL = "https://${cfg.url}";
          BEHIND_HTTPS_PROXY = "true";
          DATABASE_PATH = "/data/db.sqlite3";
          PHONEHOME = "false";
          PORT = "8000";
        };
        environmentFiles = [
          cfg.environmentFile
        ];
        ports = [
          "127.0.0.1:${toString cfg.port}:8000"
        ];
      };
    };

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:${toString cfg.port}
      '';
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${service} ${service} - -"
    ];

    environment.persistence."/".directories = [
      {
        directory = cfg.dataDir;
        user = service;
        group = service;
        mode = "0750";
      }
    ];
  };
}
