{ config, lib, ... }:
let
  hl = config.homelab;
in
{
  homelab = {
    enable = true;
    baseDomain = "magicsk.eu";
    cloudflare.dnsCredentialsFile = config.age.secrets.cloudflareDnsApiCredentials.path;
    timeZone = "Europe/Bratislava";
    mounts = {
      config = "/persist/opt/services";
      Alumentum = "/mnt/Alumentum";
      Nitor = "/mnt/Nitor";
      Wilson = "/mnt/Wilson";
      Tallow = "/mnt/Tallow";
    };
    samba = {
      enable = true;
      passwordFile = config.age.secrets.sambaPassword.path;
      shares = {
        Alumentum = {
          path = "${hl.mounts.Alumentum}/media";
        };
        Nitor = {
          path = hl.mounts.Nitor;
        };
        Wilson = {
          path = hl.mounts.Wilson;
        };
        Tallow = {
          path = hl.mounts.Tallow;
        };
        config = {
          path = hl.mounts.config;
          "follow symlinks" = "yes";
          "wide links" = "yes";
        };
        TimeMachine = {
          path = "${hl.mounts.Nitor}/TimeCapsule";
          "fruit:time machine" = "yes";
        };
      };
    };
    services = {
      enable = true;
      immich = {
        enable = true;
        mediaDir = "${hl.mounts.Nitor}/Photos";
      };
      /* homepage = {
        enable = true;
        misc = [
          {
            PiKVM =
              let
                ip = config.homelab.networks.local.lan.reservations.pikvm.Address;
              in
              {
                href = "https://${ip}";
                siteMonitor = "https://${ip}";
                description = "Open-source KVM solution";
                icon = "pikvm.png";
              };
          }
          {
            FritzBox = {
              href = "http://192.168.178.1";
              siteMonitor = "http://192.168.178.1";
              description = "Cable Modem WebUI";
              icon = "avm-fritzbox.png";
            };
          }
          {
            "Immich (Parents)" = {
              href = "https://photos.aria.goose.party";
              description = "Self-hosted photo and video management solution";
              icon = "immich.svg";
              siteMonitor = "";
            };
          }
        ];
      }; */
      homeassistant.enable = true;
      jellyfin.enable = true;
      /* paperless = {
        enable = true;
        passwordFile = config.age.secrets.paperlessPassword.path;
      }; */
      sonarr.enable = true;
      radarr.enable = true;
      prowlarr.enable = true;
      jellyseerr.enable = true;
      nextcloud = {
        enable = true;
        adminpassFile = config.age.secrets.nextcloudAdminPassword.path;
      };
      vaultwarden.enable = true;
      /* audiobookshelf.enable = true; */
      # deluge.enable = true;
    };
  };
}
