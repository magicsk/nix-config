{ config, lib, ... }:
let
  homelab = config.homelab;
  cfg = config.homelab.services.otbr;
in
{
  options.homelab.services.otbr = {
    enable = lib.mkEnableOption {
      description = "Enable OpenThread Border Router";
    };
    configDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/otbr";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "otbr.${homelab.baseDomain}";
    };
  };
  config = lib.mkIf cfg.enable {
    networking.firewall.allowedUDPPorts = [ 61631 ];
    environment.persistence."/" = {
      directories = [
        { directory = cfg.configDir; user = "root"; group = "root"; mode = "0755"; }
      ];
    };
    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:8081
      '';
    };
    virtualisation = {
      podman.enable = true;
      oci-containers = {
        containers = {
          otbr = {
            image = "openthread/border-router:latest";
            autoStart = true;
            extraOptions = [
              "--pull=newer"
              "--network=host"
              "--privileged"
              "--cap-add=NET_ADMIN"
              "--device=/dev/serial/by-id/usb-1a86_USB_Single_Serial_58CF091384-if00:/dev/ttyACM0"
              "--device=/dev/net/tun:/dev/net/tun"
            ];
            volumes = [
              "${cfg.configDir}:/data"
            ];
            environment = {
              OT_RCP_DEVICE = "spinel+hdlc+uart:///dev/ttyACM0?uart-baudrate=460800";
              OT_INFRA_IF = "br0";
              OT_THREAD_IF = "wpan0";
              OT_REST_LISTEN_ADDR = "0.0.0.0";
              OT_REST_LISTEN_PORT = "8081";
              OT_LOG_LEVEL = "2";
            };
          };
        };
      };
    };
  };
}
