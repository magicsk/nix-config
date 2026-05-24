{ config, lib, ... }:
let
  service = "transi-eu";
  homelab = config.homelab;
  cfg = config.homelab.services.websites.${service};
in
{
  options.homelab.services.websites.${service}.enable = lib.mkEnableOption "Website ${service}";

  config = lib.mkIf (config.homelab.services.websites.enable && cfg.enable) {
    services.git-websites.sites.${service} = {
      host = "transi.eu";
      repo = "git@github.com:magicsk/transi.eu.git";
      dataDir = "${homelab.mounts.config}/websites/${service}";
      kind = "backend";
      port = 8032;
      user = homelab.user;
      group = homelab.group;
      home = "/home/${homelab.user}";
      buildCommand = "bun run build";
      startCommand = "bun run start";
      acmeCredentialsFile = homelab.cloudflare.dnsCredentialsFile;
      homepage = {
        name = "Transi";
        description = "Site about the app";
        icon = "mdi-train";
      };
    };

    homelab.services.reservedPorts = [
      {
        name = "website-${service}";
        port = 8032;
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
