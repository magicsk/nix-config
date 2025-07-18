{ config, lib, ... }:
let
  service = "prowlarr";
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
      default = "/persist/opt/services/${service}";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "${service}.${homelab.baseDomain}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Prowlarr";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "PVR indexer";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "prowlarr.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Arr";
    };
  };
  config = lib.mkIf cfg.enable {
    services = {
      ${service} = {
        enable = true;
      };
      caddy.virtualHosts."${cfg.url}" = {
        useACMEHost = homelab.baseDomain;
        extraConfig = ''
          reverse_proxy http://127.0.0.1:9696
        '';
      };
    };
    systemd = {
      tmpfiles.rules = [
        "d ${cfg.dataDir} 0777 ${homelab.user} ${homelab.group} -"
      ];
      services.${service}.serviceConfig = {
        ExecStart = lib.mkForce "${lib.getExe config.services.${service}.package} -nobrowser -data=${cfg.dataDir}";
        ReadWritePaths = [ cfg.dataDir ];
      };
    };
  };
}
