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
      };
      homepage = {
        enable = true;
        misc = [
          {
            "Router" = {
              href = "http://magic-port.local";
              siteMonitor = "http://magic-port.local";
              description = "OpenWrt WebUI";
              icon = "sh-openwrt-light.svg";
            };
          }
          {
            "Access point" = {
              href = "http://wifi-ap.local";
              siteMonitor = "http://wifi-ap.local";
              description = "WiFi AP WebUI";
              icon = "mdi-wifi";
            };
          }
        ];
      };
      homeassistant.enable = true;
      mosquitto.enable = true;
      zigbee2mqtt.enable = true;
      jellyfin.enable = true;
      paperless = {
        enable = true;
        passwordFile = config.age.secrets.paperlessPassword.path;
      };
      sonarr.enable = true;
      radarr.enable = true;
      prowlarr.enable = true;
      jellyseerr.enable = true;
      nextcloud = {
        enable = true;
        adminpassFile = config.age.secrets.nextcloudAdminPassword.path;
      };
      vaultwarden.enable = true;
      qbittorrent.enable = true;
      redlib.enable = true;
      code-server = {
        enable = true;
        passFile = config.age.secrets.codeServerPassword.path;
        passSudoFile = config.age.secrets.codeServerSudoPassword.path;
      };
      /* audiobookshelf.enable = true; */
    };
  };
}
