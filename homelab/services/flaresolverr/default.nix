{ config, lib, ... }:
let
  service = "flaresolverr";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
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
        environment = {
          TZ = homelab.timeZone;
          LOG_LEVEL = "info";
        };
      };
    };
  };
}
