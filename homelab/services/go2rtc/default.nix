{ config, lib, ... }:
let
  service = "go2rtc";
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
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "go2rtc";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Camera streaming";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "go2rtc.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Smart Home";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation = {
      podman.enable = true;
      oci-containers.containers.${service} = {
        image = "alexxit/go2rtc";
        volumes = [
          "${cfg.dataDir}:/config"
          "/dev:/dev"
        ];
        extraOptions = [
          "--device-cgroup-rule=c 81:* rmw" # video4linux
          "--group-add=video"
          "--network=host"
        ];
        environment = {
          TZ = homelab.timeZone;
        };
      };
    };

    # host networking exposes ports directly, open for LAN access
    networking.firewall.allowedTCPPorts = [ 1984 8555 ];
    networking.firewall.allowedUDPPorts = [ 8555 ];

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:1984
      '';
    };

    environment.persistence."/".directories = [
      { directory = cfg.dataDir; user = homelab.user; group = homelab.group; mode = "0755"; }
    ];
  };
}
