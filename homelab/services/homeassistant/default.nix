{ config, lib, ... }:
let
  homelab = config.homelab;
  cfg = config.homelab.services.homeassistant;
in
{
  options.homelab.services.homeassistant = {
    enable = lib.mkEnableOption {
      description = "Enable Home Assistant";
    };
    configDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/homeassistant";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "home.${homelab.baseDomain}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Home Assistant";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Home automation platform";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "home-assistant.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Smart Home";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.persistence."/" = {
      directories = [
        { directory = cfg.configDir; user = homelab.user; group = homelab.group; mode = "0775"; }
      ];
    };
    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:8123
      '';
    };
    virtualisation = {
      podman.enable = true;
      oci-containers = {
        containers = {
          homeassistant = {
            image = "homeassistant/home-assistant:stable";
            autoStart = true;
            extraOptions = [
              "--pull=newer"
            ];
            volumes = [
              "${cfg.configDir}:/config"
              "${homelab.mounts.Alumentum}:/mnt/Alumentum"
              "${homelab.mounts.Nitor}:/mnt/Nitor"
              "${homelab.mounts.Wilson}:/mnt/Wilson"
            ];
            ports = [
              "0.0.0.0:8123:8123"
              "0.0.0.0:8124:80"
            ];
            environment = {
              TZ = homelab.timeZone;
              PUID = toString config.users.users.${homelab.user}.uid;
              PGID = toString config.users.groups.${homelab.group}.gid;
            };
          };
        };
      };
    };
  };
}
