{ config, lib, ... }:
let
  homelab = config.homelab;
  cfg = config.homelab.services.matter-server;
in
{
  options.homelab.services.matter-server = {
    enable = lib.mkEnableOption {
      description = "Enable Matter Server (Python Matter Server)";
    };
    configDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/matter-server";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "matter.${homelab.baseDomain}";
    };
  };
  config = lib.mkIf cfg.enable {
    networking.firewall = {
      allowedUDPPorts = [ 5353 5540 ];
    };

    boot.kernel.sysctl = {
      # Enable IPv6 Forwarding so packets can move between br0 and wpan0
      "net.ipv6.conf.a-.accept_ra_rt_info_max_plen" = 64;
      "net.ipv6.conf.br0.accept_ra_rt_info_max_plen" = 64;

      # Optimize multicast handling for Matter/mDNS
      "net.ipv6.conf.all.mldv2_force_sysctl" = 1;
    };

    environment.persistence."/" = {
      directories = [
        { directory = cfg.configDir; user = "root"; group = "root"; mode = "0755"; }
      ];
    };

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:5580
      '';
    };

    virtualisation = {
      podman.enable = true;
      oci-containers = {
        containers = {
          matter-server = {
            image = "ghcr.io/home-assistant-libs/python-matter-server:stable";
            autoStart = true;
            extraOptions = [
              "--pull=newer"
              "--network=host"
              # "--privileged"
              "--cap-add=NET_ADMIN"
              "--cap-add=NET_RAW"
            ];
            volumes = [
              "${cfg.configDir}:/data"
            ];
            cmd = [
              "--storage-path" "/data"
              "--primary-interface" "br0"
            ];
          };
        };
      };
    };
  };
}
