{ config, lib, pkgs, ... }:
let
  service = "affine";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
  dbPassword = "affine";
  affineImage = "ghcr.io/toeverything/affine:stable";
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable ${service}";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/${service}";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "${service}.${homelab.baseDomain}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "AFFiNE";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Knowledge Base & Workspace";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "affine.svg";
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
        "${service}-postgres" = {
          image = "pgvector/pgvector:pg16";
          volumes = [
            "${cfg.dataDir}/postgres:/var/lib/postgresql/data"
          ];
          environment = {
            POSTGRES_USER = service;
            POSTGRES_PASSWORD = dbPassword;
            POSTGRES_DB = service;
            POSTGRES_INITDB_ARGS = "--data-checksums";
            POSTGRES_HOST_AUTH_METHOD = "trust";
          };
        };
        "${service}-redis" = {
          image = "redis:latest";
        };
        ${service} = {
          image = affineImage;
          volumes = [
            "${cfg.dataDir}/storage:/root/.affine/storage"
            "${cfg.dataDir}/config:/root/.affine/config"
          ];
          environment = {
            AFFINE_SERVER_EXTERNAL_URL = "https://${cfg.url}";
            AFFINE_INDEXER_ENABLED = "false";
            REDIS_SERVER_HOST = "${service}-redis";
            DATABASE_URL = "postgresql://${service}:${dbPassword}@${service}-postgres:5432/${service}";
          };
          ports = [
            "3010:3010"
          ];
          dependsOn = [
            "${service}-postgres"
            "${service}-redis"
          ];
        };
      };
    };

    systemd.services."podman-${service}" = {
      requires = [ "${service}-migration.service" ];
      after = [ "${service}-migration.service" ];
    };

    systemd.services."${service}-migration" = {
      description = "AFFiNE database migration";
      requires = [ "podman-${service}-postgres.service" "podman-${service}-redis.service" ];
      after = [ "podman-${service}-postgres.service" "podman-${service}-redis.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.podman}/bin/podman run --rm --name ${service}-migration -v ${cfg.dataDir}/storage:/root/.affine/storage -v ${cfg.dataDir}/config:/root/.affine/config -e AFFINE_INDEXER_ENABLED=false -e REDIS_SERVER_HOST=${service}-redis -e 'DATABASE_URL=postgresql://${service}:${dbPassword}@${service}-postgres:5432/${service}' ${affineImage} sh -c 'node ./scripts/self-host-predeploy.js'";
      };
    };

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:3010
      '';
    };

    environment.persistence."/" = {
      directories = [
        { directory = "${cfg.dataDir}/storage"; user = homelab.user; group = homelab.group; mode = "0755"; }
        { directory = "${cfg.dataDir}/config"; user = homelab.user; group = homelab.group; mode = "0755"; }
        { directory = "${cfg.dataDir}/postgres"; user = homelab.user; group = homelab.group; mode = "0755"; }
      ];
    };
  };
}
