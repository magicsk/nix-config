{
  config,
  lib,
  pkgs,
  ...
}:
let
  homelab = config.homelab;
  cfg = config.homelab.services.homeassistant;
  homeassistantUid = config.users.users.${homelab.user}.uid;
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
    services.udev.extraRules = ''
      KERNEL=="video[0-9]*", MODE="0666"
    '';

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

    # Home Assistant runs on the host network as homelab.user via linuxserver's PUID.
    # GitHub rejects TLS handshakes from the WireGuard VPS path, which breaks HACS downloads.
    networking.wg-quick.interfaces.wg0.postUp = ''
      ${pkgs.iproute2}/bin/ip rule add uidrange ${toString homeassistantUid}-${toString homeassistantUid} table main priority 86
    '';
    networking.wg-quick.interfaces.wg0.preDown = ''
      ${pkgs.iproute2}/bin/ip rule del uidrange ${toString homeassistantUid}-${toString homeassistantUid} table main priority 86 || true
    '';

    virtualisation = {
      podman.enable = true;
      oci-containers = {
        containers = {
          homeassistant = {
            image = "linuxserver/homeassistant:latest";
            autoStart = true;
            extraOptions = [
              "--pull=newer"
              "--network=host"
              # "--privileged"
              "--cap-add=NET_ADMIN"
              "--cap-add=NET_RAW"
              "--device-cgroup-rule=c 81:* rmw"
              "--group-add=video"
            ];
            volumes = [
              "/dev:/dev"
              "${cfg.configDir}:/config"
              "${homelab.mounts.Nitor}/Backups/hass:/config/backups"
              "${homelab.mounts.Alumentum}:/mnt/Alumentum"
              "${homelab.mounts.Nitor}:/mnt/Nitor"
              "${homelab.mounts.Wilson}:/mnt/Wilson"
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
