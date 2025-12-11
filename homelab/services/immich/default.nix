{ config, lib, ... }:
let
  service = "immich";
  cfg = config.homelab.services.immich;
  homelab = config.homelab;
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption "Self-hosted photo and video management solution";
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${homelab.mounts.config}/${service}";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "photos.${homelab.baseDomain}";
    };
    altUrl = lib.mkOption {
      type = lib.types.str;
      default = "immich.${homelab.baseDomain}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Immich";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Self-hosted photo and video management solution";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "immich.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Media";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.persistence."/" = {
      directories = [
        { directory = cfg.dataDir; user = service; group = homelab.group; mode = "0755"; }
      ];
    };
    systemd.services.immich-server.serviceConfig.UMask = lib.mkForce "0007";
    fileSystems."${cfg.dataDir}/library" = {
      device = "${config.homelab.mounts.Nitor}/Photos";
      options = [ "bind" ];
    };
    users.users.${service}.extraGroups = [
      "video"
      "render"
    ];
    services.${service} = {
      group = homelab.group;
      enable = true;
      host = "0.0.0.0";
      port = 2283;
      mediaLocation = "${cfg.dataDir}";
    };
    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://${config.services.immich.host}:${toString config.services.immich.port} {
          header_up Transfer-Encoding chunked
        }
      '';
    };
    services.caddy.virtualHosts."${cfg.altUrl}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://${config.services.immich.host}:${toString config.services.immich.port} {
          header_up Transfer-Encoding chunked
        }
      '';
    };
  };

}
