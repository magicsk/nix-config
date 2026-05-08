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
    url = lib.mkOption {
      type = lib.types.str;
      default = "${service}.${homelab.baseDomain}";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8020;
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
      default = "bugsink.svg";
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

    environment.persistence."/".directories = [
      {
        directory = cfg.dataDir;
        user = homelab.user;
        group = homelab.group;
        mode = "0755";
      }
    ];
  };
}
