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
      default = "${homelab.mounts.config}/${service}";
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
    environment.persistence."/" = {
      directories = [
        { directory = cfg.dataDir; user = homelab.user; group = homelab.group; mode = "0777"; }
      ];
    };
    systemd.services.${service}.serviceConfig = {
      ExecStart = lib.mkForce "${lib.getExe config.services.${service}.package} -nobrowser -data=${cfg.dataDir}";
      ReadWritePaths = [ cfg.dataDir ];
    };
  };
}
