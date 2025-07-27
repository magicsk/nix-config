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
  };
  config = lib.mkIf cfg.enable {
    services.${service} = {
      enable = true;
    };
    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:1883
      '';
    };
    systemd = {
      tmpfiles.rules = [
        "d ${cfg.dataDir} 0777 ${homelab.user} ${homelab.group} -"
      ];
    };
  };

}
