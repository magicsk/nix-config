{
  config,
  pkgs,
  lib,
  ...
}:
let
  service = "zigbee2mqtt";
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
      default = "Zigbee2MQTT";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Zigbee2MQTT is a bridge between Zigbee networks and MQTT";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "zigbee2mqtt.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Smart Home";
    };
  };
  config = lib.mkIf cfg.enable {
    services.${service} = {
      enable = true;
      package = pkgs.zigbee2mqtt_2;
      dataDir = cfg.dataDir;
      settings = {
        homeassistant = true;
        permit_join = true;
        frontend = true;
        # not working
        # host = "127.0.0.1";
        # port = "8181";
        serial = {
          adapter = "ember";
          rtscts = true;
          port = "/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0";
        };
      };
    };
    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:8080
      '';
    };
    environment.persistence."/".directories = [
      { directory = cfg.dataDir; user = homelab.user; group = homelab.group; mode = "0777"; }
    ];
  };

}
