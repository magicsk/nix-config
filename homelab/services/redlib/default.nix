{ config, lib, pkgs, ... }:
let
  service = "redlib";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
  networkSubnet = "172.30.16.0/24";
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable ${service}";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "redlib.${homelab.baseDomain}";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8282;
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "redlib";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Alternative front-end for reddit";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "redlib.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
    };
    homepage.siteMonitor = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether homepage should probe ${service} for status.";
    };
  };
  config = lib.mkIf cfg.enable {
    # Track the upstream container instead of the nixpkgs build: Reddit's anti-bot
    # edge blocks redlib's older client fingerprint (403/401 on OAuth), and the fix
    # (wreq-based TLS emulation) only ships on recent upstream builds.
    virtualisation = {
      podman.enable = true;
      oci-containers.containers.${service} = {
        image = "quay.io/redlib/redlib:latest";
        autoStart = true;
        ports = [
          "127.0.0.1:${toString cfg.port}:8080"
        ];
        extraOptions = [
          "--network=${service}"
          "--read-only"
          "--security-opt=no-new-privileges"
          "--cap-drop=ALL"
          "--user=nobody"
        ];
        environment = {
          TZ = homelab.timeZone;
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

    # Reddit blocks the VPS public IP, so redlib must reach Reddit through the home
    # WAN. Route its container subnet around the WireGuard tunnel.
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
  };

}
