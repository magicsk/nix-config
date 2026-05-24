{ config, lib, pkgs, ... }:
let
  service = "paperless";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
  networkSubnet = "172.30.13.0/24";
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
          extraOptions = [ "--network=${service}" ];
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
          extraOptions = [ "--network=${service}" ];
          dependsOn = [ "${service}-redis" ];
        };
      };
    };

    systemd.services."podman-network-${service}" = {
      description = "Create Podman network for ${service}";
      before = [
        "podman-${service}.service"
        "podman-${service}-redis.service"
      ];
      after = [ "podman.service" ];
      requiredBy = [
        "podman-${service}.service"
        "podman-${service}-redis.service"
      ];
      path = [ pkgs.podman ];
      script = ''
        podman network inspect ${service} > /dev/null 2>&1 || \
          podman network create --subnet ${networkSubnet} ${service}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    networking.wg-quick.interfaces.wg0.postUp = ''
      ${pkgs.iproute2}/bin/ip rule add from ${networkSubnet} table main priority 86
    '';
    networking.wg-quick.interfaces.wg0.preDown = ''
      ${pkgs.iproute2}/bin/ip rule del from ${networkSubnet} table main priority 86 || true
    '';

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
