{ config, lib, ... }:
let
  service = "headscale";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable ${service} reverse proxy";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "hs.${homelab.baseDomain}";
    };
    upstream = lib.mkOption {
      type = lib.types.str;
      default = "http://172.16.16.1:8080";
      description = "Headscale HTTP upstream reachable from magic-pylon.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy ${cfg.upstream}
      '';
    };
  };
}
