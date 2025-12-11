{ config, lib, ... }:
let
  service = "esphome";
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
      default = "ESPHome";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "An open-source firmware framework";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "esphome.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Smart Home";
    };
  };
  config = lib.mkIf cfg.enable {
    services = {
      esphome = {
        enable = true;
        openFirewall = true;
      };
      caddy.virtualHosts."${cfg.url}" = {
        useACMEHost = homelab.baseDomain;
        extraConfig = ''
          reverse_proxy http://127.0.0.1:${toString config.services.${service}.port}
        '';
      };
    };
    systemd.services.${service} = {
      environment = lib.mkForce {
        # platformio fails to determine the home directory when using DynamicUser
        PLATFORMIO_CORE_DIR = "${cfg.dataDir}/.platformio";
      };
      serviceConfig = lib.mkForce {
        ExecStart = "${config.services.${service}.package}/bin/esphome dashboard --address 127.0.0.1 --port ${toString config.services.${service}.port} ${cfg.dataDir}";
        WorkingDirectory = cfg.dataDir;
      };
    };
    environment.persistence."/".directories = [
      { directory = cfg.dataDir; user = service; group = service; mode = "0777"; }
    ];
  };

}
