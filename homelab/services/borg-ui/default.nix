{ config, lib, ... }:
let
  service = "borg-ui";
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
      default = "borg.${homelab.baseDomain}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Borg-UI";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "BorgBackup Web Interface";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "borg.svg";
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
        image = "ainullcode/borg-ui:latest";
        volumes = [
          "${cfg.dataDir}/data:/data"
          "${cfg.dataDir}/cache:/home/borg/.cache/borg"
          "${homelab.mounts.Nitor}:/local/Nitor:rw"
          "${homelab.mounts.Alumentum}:/local/Alumentum:rw"
          "${homelab.mounts.config}:/local/Services:ro"
          "/etc/localtime:/etc/localtime:ro"
        ];
        environment = {
          TZ = homelab.timeZone;
          PUID = toString config.users.users.${homelab.user}.uid;
          PGID = toString config.users.groups.${homelab.group}.gid;
        };
        ports = [
          "127.0.0.1:8084:8081"
        ];
      };
    };

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:8084
      '';
    };

    environment.persistence."/" = {
      directories = [
        { directory = "${cfg.dataDir}/data"; user = homelab.user; group = homelab.group; mode = "0755"; }
        { directory = "${cfg.dataDir}/cache"; user = homelab.user; group = homelab.group; mode = "0755"; }
      ];
    };
  };
}
