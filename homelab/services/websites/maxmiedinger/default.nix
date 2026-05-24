{ config, lib, ... }:
let
  service = "maxmiedinger";
  homelab = config.homelab;
  cfg = config.homelab.services.websites.${service};
in
{
  options.homelab.services.websites.${service}.enable = lib.mkEnableOption "Website ${service}";

  config = lib.mkIf (config.homelab.services.websites.enable && cfg.enable) {
    services.git-websites.sites.${service} = {
      host = "maxmiedinger.magicsk.eu";
      repo = "git@github.com:magicsk/maxmiedinger.git";
      dataDir = "${homelab.mounts.config}/websites/${service}";
      user = homelab.user;
      group = homelab.group;
      home = "/home/${homelab.user}";
      installCommand = "";
      webRoot = ".";
      acmeHost = homelab.baseDomain;
      manageAcme = false;
      homepage = {
        name = "Max Miedinger";
        description = "Typography website";
        icon = "mdi-format-font";
      };
    };

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
