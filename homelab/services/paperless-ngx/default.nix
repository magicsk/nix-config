{ config, lib, ... }:
let
  service = "paperless";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable ${service}";
    };
    mediaDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.Nitor}/Documents/Paperless/Documents";
    };
    consumptionDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.Nitor}/Documents/Paperless/Import";
    };
    passwordFile = lib.mkOption {
      type = lib.types.path;
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/${service}";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "paperless.${homelab.baseDomain}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Paperless-ngx";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Document management system";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "paperless.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
    };

  };
  config = lib.mkIf cfg.enable {
    services = {
      ${service} = {
        enable = true;
        passwordFile = cfg.passwordFile;
        user = homelab.user;
        dataDir = cfg.dataDir;
        mediaDir = cfg.mediaDir;
        consumptionDir = cfg.consumptionDir;
        consumptionDirIsPublic = true;
        settings = {
          PAPERLESS_CONSUMER_IGNORE_PATTERN = [
            ".DS_STORE/*"
            "desktop.ini"
          ];
          PAPERLESS_OCR_LANGUAGE = "slk+eng";
          PAPERLESS_URL = "https://${cfg.url}";
          PAPERLESS_OCR_USER_ARGS = {
            optimize = 1;
            pdfa_image_compression = "lossless";
          };
        };
      };
      caddy.virtualHosts."${cfg.url}" = {
        useACMEHost = homelab.baseDomain;
        extraConfig = ''
          reverse_proxy http://127.0.0.1:${toString config.services.${service}.port}
        '';
      };
    };
    systemd.tmpfiles.rules = [
      "d ${homelab.mounts.Nitor}/Documents/Paperless 0777 ${homelab.user} ${homelab.group} - -"
      "d ${cfg.dataDir} 0777 ${homelab.user} ${homelab.group} - -"
      "d ${cfg.mediaDir} 0777 ${homelab.user} ${homelab.group} - -"
      "d ${cfg.consumptionDir} 0777 ${homelab.user} ${homelab.group} - -"
    ];
  };
}
