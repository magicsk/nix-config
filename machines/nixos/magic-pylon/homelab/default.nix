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
    };
    samba = {
      enable = true;
      passwordFile = config.age.secrets.sambaPassword.path;
      shares = {
        Alumentum = {
          path = "${hl.mounts.Alumentum}";
        };
        Nitor = {
          path = hl.mounts.Nitor;
        };
        Wilson = {
          path = hl.mounts.Wilson;
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
      borg-ui.enable = true;
      homepage = {
        enable = true;
        misc = [
          {
            "Router" = {
              href = "http://magic-port.local";
              siteMonitor = "http://magic-port.local";
              description = "OpenWrt";
              icon = "sh-openwrt-light.svg";
            };
          }
          {
            "Access point" = {
              href = "http://wifi-ap.local";
              siteMonitor = "http://wifi-ap.local";
              description = "WiFi AP";
              icon = "mdi-wifi";
            };
          }
          {
            "ISP Box" = {
              href = "http://192.168.100.1";
              siteMonitor = "http://192.168.100.1";
              description = "ISP Box";
              icon = "mdi-lan";
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
      jellyseerr.enable = false;
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
      esphome.enable = true;
      otbr.enable = true;
      matter-server.enable = true;
      minecraft = {
        enable = false;
        name = "monifactory";
      };
    };
  };
}
