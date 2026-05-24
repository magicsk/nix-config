{ config, lib, ... }:
let
  service = "reciper";
  homelab = config.homelab;
  cfg = config.homelab.services.websites.${service};
in
{
  options.homelab.services.websites.${service}.enable = lib.mkEnableOption "Website ${service}";

  config = lib.mkIf (config.homelab.services.websites.enable && cfg.enable) {
    services.git-websites.sites.${service} = {
      host = "reciper.magicsk.eu";
      repo = "git@github.com:magicsk/reciper.git";
      dataDir = "${homelab.mounts.config}/websites/${service}";
      kind = "backend";
      port = 8031;
      user = homelab.user;
      group = homelab.group;
      home = "/home/${homelab.user}";
      buildCommand = "bun run build";
      startCommand = "mkdir -p data && bun run start";
      acmeHost = homelab.baseDomain;
      manageAcme = false;
      homepage = {
        name = "Reciper";
        description = "Recipe app";
        icon = "mdi-silverware-fork-knife";
      };
    };

    homelab.services.reservedPorts = [
      {
        name = "website-${service}";
        port = 8031;
      }
    ];

    environment.persistence."/".directories = [
      {
        directory = "${homelab.mounts.config}/websites/${service}";
        user = homelab.user;
        group = homelab.group;
        mode = "0755";
      }
    ];
  };
}
