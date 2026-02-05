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
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "OpenThread Border Router";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Thread border router";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "matter.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Smart Home";
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
        reverse_proxy http://127.0.0.1:8085
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
              "--cap-add=NET_RAW"
              "--device=/dev/serial/by-id/usb-1a86_USB_Single_Serial_58CF091384-if00:/dev/ttyACM0"
              "--device=/dev/net/tun:/dev/net/tun"
            ];
            volumes = [
              "${cfg.configDir}:/data"
              "/run/dbus/system_bus_socket:/run/dbus/system_bus_socket"
            ];
            environment = {
              OT_RCP_DEVICE = "spinel+hdlc+uart:///dev/ttyACM0?uart-baudrate=460800&uart-flow-control";
              OT_INFRA_IF = "br0";
              OT_THREAD_IF = "wpan0";
              OT_REST_LISTEN_ADDR = "0.0.0.0";
              OT_REST_LISTEN_PORT = "8081";
              OT_WEB_LISTEN_ADDR = "0.0.0.0";
              OT_WEB_LISTEN_PORT = "8085";
              OT_BR_NAME = "magic-pylon-otbr";
              OT_LOG_LEVEL = "2";
            };
          };
        };
      };
    };
  };
}
