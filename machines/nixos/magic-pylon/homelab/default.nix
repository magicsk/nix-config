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
      reservedPorts = [
        {
          name = "external-8020";
          port = 8020;
        }
      ];
      immich.enable = true;
      borg-ui.enable = true;
      homepage = {
        enable = true;
        network = [
          {
            "Router" = {
              href = "http://magic-port.local";
              description = "OpenWrt";
              icon = "sh-openwrt-light.svg";
            };
          }
          {
            "Access point" = {
              href = "http://wifi-ap.local";
              description = "WiFi AP";
              icon = "mdi-wifi";
            };
          }
          {
            "ISP Box" = {
              href = "http://192.168.100.1";
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
      plausible = {
        enable = true;
        url = "pl.${config.homelab.baseDomain}";
        secretKeybaseFile = config.age.secrets.plausibleSecretKeybase.path;
      };
      bugsink = {
        enable = true;
        url = "bs.${config.homelab.baseDomain}";
        environmentFile = config.age.secrets.bugsinkEnv.path;
      };
      changedetection-io.enable = true;
      html2rss-web.enable = true;
      code-server = {
        enable = true;
        passFile = config.age.secrets.codeServerPassword.path;
        passSudoFile = config.age.secrets.codeServerSudoPassword.path;
      };
      codex-wrapper.enable = true;
      open-webui.enable = true;
      esphome.enable = true;
      otbr.enable = true;
      matter-server.enable = true;
      minecraft = {
        enable = true;
        name = "monifactory";
      };
      affine.enable = true;
      flaresolverr.enable = true;
      go2rtc.enable = true;
      headscale.enable = true;
      obico-ml.enable = true;
      trakt-backup.enable = true;
      stalwart = {
        enable = true;
        resendApiKeyFile = config.age.secrets.resendApiKey.path;
        adminPasswordFile = config.age.secrets.stalwartAdminPassword.path;
      };
      websites = {
        enable = true;
        startpage.enable = true;
        api.enable = true;
        maxmiedinger.enable = true;
        reciper.enable = true;
        transi-eu.enable = true;
      };
    };
  };
}
