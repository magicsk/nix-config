{ config, lib, pkgs, ... }:
let
  service = "flaresolverr";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
  networkSubnet = "172.30.12.0/24";
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable ${service}";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation = {
      podman.enable = true;
      oci-containers.containers.${service} = {
        image = "ghcr.io/flaresolverr/flaresolverr:latest";
        ports = [
          "8191:8191"
        ];
        extraOptions = [ "--network=${service}" ];
        environment = {
          TZ = homelab.timeZone;
          LOG_LEVEL = "info";
        };
      };
    };

    # Create a dedicated Podman network so its subnet can be routed around the VPN
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

    # Exempt flaresolverr's subnet from the WireGuard VPN so it uses the local connection
    networking.wg-quick.interfaces.wg0.postUp = ''
      ${pkgs.iproute2}/bin/ip rule add from ${networkSubnet} table main priority 86
    '';
    networking.wg-quick.interfaces.wg0.preDown = ''
      ${pkgs.iproute2}/bin/ip rule del from ${networkSubnet} table main priority 86 || true
    '';
  };
}
