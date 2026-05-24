{ config, lib, ... }:
let
  service = "api";
  homelab = config.homelab;
  cfg = config.homelab.services.websites.${service};
in
{
  options.homelab.services.websites.${service}.enable = lib.mkEnableOption "Website ${service}";

  config = lib.mkIf (config.homelab.services.websites.enable && cfg.enable) {
    services.git-websites.sites.${service} = {
      host = "api.magicsk.eu";
      repo = "git@github.com:magicsk/api.git";
      dataDir = "${homelab.mounts.config}/websites/${service}";
      kind = "backend";
      port = 8030;
      user = homelab.user;
      group = homelab.group;
      home = "/home/${homelab.user}";
      startCommand = "bun run start";
      caddyExtraConfig = ''
        @plausible path /j/ps.js /a/e
        handle @plausible {
          rewrite /j/ps.js /js/script.hash.outbound-links.js
          rewrite /a/e /api/event
          reverse_proxy https://pl.${homelab.baseDomain} {
            header_up Host pl.${homelab.baseDomain}
            header_up X-Forwarded-For {http.request.remote.host}
          }
        }
      '';
      acmeHost = homelab.baseDomain;
      manageAcme = false;
      homepage = {
        name = "API";
        description = "Public API";
        icon = "mdi-api";
        siteMonitorUrl = "https://api.${homelab.baseDomain}/timetable/manifest";
      };
    };

    homelab.services.reservedPorts = [
      {
        name = "website-${service}";
        port = 8030;
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
