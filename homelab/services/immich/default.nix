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
      default = "${config.homelab.mounts.config}/${service}";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "photos.${homelab.baseDomain}";
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
    systemd = {
      tmpfiles.rules = [ "d ${cfg.dataDir} 0775 ${service} ${homelab.group} - -" ];
      services.immich-server.serviceConfig.UMask = lib.mkForce "0007";
    };
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
      port = 2283;
      mediaLocation = "${cfg.dataDir}";
    };
    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://${config.services.immich.host}:${toString config.services.immich.port}
      '';
    };
  };

}
