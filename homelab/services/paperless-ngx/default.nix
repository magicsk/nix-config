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
    virtualisation = {
      podman.enable = true;
      oci-containers.containers = {
        "${service}-redis" = {
          image = "redis:latest";
        };
        ${service} = {
          image = "ghcr.io/paperless-ngx/paperless-ngx:latest";
          volumes = [
            "${cfg.dataDir}/data:/usr/src/paperless/data"
            "${cfg.mediaDir}:/usr/src/paperless/media"
            "${cfg.consumptionDir}:/usr/src/paperless/consume"
          ];
          environment = {
            PAPERLESS_REDIS = "redis://${service}-redis:6379";
            PAPERLESS_URL = "https://${cfg.url}";
            PAPERLESS_OCR_LANGUAGE = "slk+eng";
            PAPERLESS_OCR_LANGUAGES = "slk";
            PAPERLESS_OCR_USER_ARGS = builtins.toJSON {
              optimize = 1;
              pdfa_image_compression = "lossless";
            };
            PAPERLESS_CONSUMER_IGNORE_PATTERN = builtins.toJSON [
              ".DS_STORE/*"
              "desktop.ini"
            ];
            PAPERLESS_CONSUMER_RECURSIVE = "true";
            USERMAP_UID = "1000";
            USERMAP_GID = "1000";
          };
          environmentFiles = [
            cfg.passwordFile
          ];
          ports = [
            "127.0.0.1:8000:8000"
          ];
          dependsOn = [ "${service}-redis" ];
        };
      };
    };

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:8000
      '';
    };

    environment.persistence."/".directories = [
      { directory = "${homelab.mounts.Nitor}/Documents/Paperless"; user = homelab.user; group = homelab.group; mode = "0777"; }
      { directory = "${cfg.dataDir}/data"; user = homelab.user; group = homelab.group; mode = "0777"; }
      { directory = cfg.mediaDir; user = homelab.user; group = homelab.group; mode = "0777"; }
      { directory = cfg.consumptionDir; user = homelab.user; group = homelab.group; mode = "0777"; }
    ];
  };
}
