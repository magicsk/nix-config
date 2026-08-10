{
  config,
  lib,
  pkgs,
  ...
}:
let
  service = "crosswatch";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
  networkSubnet = "172.30.18.0/24";
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption "CrossWatch media sync";
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
      default = 8787;
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "CrossWatch";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Media watch-state sync";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "sh-crosswatch";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Media";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation = {
      podman.enable = true;
      oci-containers.containers.${service} = {
        image = "ghcr.io/cenodude/crosswatch:latest";
        autoStart = true;
        ports = [ "127.0.0.1:${toString cfg.port}:8787" ];
        volumes = [ "${cfg.dataDir}:/config" ];
        environment = {
          APP_UID = toString config.users.users.${homelab.user}.uid;
          APP_GID = toString config.users.groups.${homelab.group}.gid;
          TZ = homelab.timeZone;
        };
        extraOptions = [ "--network=${service}" ];
      };
    };

    systemd.services."podman-network-${service}" = {
      description = "Create Podman network for ${service}";
      before = [ "podman-${service}.service" ];
      after = [ "podman.service" ];
      requiredBy = [ "podman-${service}.service" ];
      path = [ pkgs.podman ];
      script = ''
        podman network inspect ${service} > /dev/null 2>&1 || \
          podman network create --subnet ${networkSubnet} ${service}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    networking.wg-quick.interfaces.wg0.postUp = ''
      ${pkgs.iproute2}/bin/ip rule add from ${networkSubnet} table main priority 86
    '';
    networking.wg-quick.interfaces.wg0.preDown = ''
      ${pkgs.iproute2}/bin/ip rule del from ${networkSubnet} table main priority 86 || true
    '';

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
