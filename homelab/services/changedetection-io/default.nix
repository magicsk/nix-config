{ config, lib, ... }:
let
  service = "changedetection-io";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable changedetection.io";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/${service}";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "changedetection.${homelab.baseDomain}";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "changedetection.io";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Website change monitoring";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "sh-changedetection";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation = {
      podman.enable = true;
      oci-containers.containers.${service} = {
        image = "docker.io/dgtlmoon/changedetection.io:latest";
        autoStart = true;
        volumes = [
          "${cfg.dataDir}:/datastore"
        ];
        ports = [
          "127.0.0.1:${toString cfg.port}:5000"
        ];
        environment = {
          TZ = homelab.timeZone;
          BASE_URL = "https://${cfg.url}";
          USE_X_SETTINGS = "1";
          PORT = "5000";
          PUID = toString config.users.users.${homelab.user}.uid;
          PGID = toString config.users.groups.${homelab.group}.gid;
        };
      };
    };

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:${toString cfg.port}
      '';
    };

    environment.persistence."/".directories = [
      { directory = cfg.dataDir; user = homelab.user; group = homelab.group; mode = "0775"; }
    ];
  };
}
