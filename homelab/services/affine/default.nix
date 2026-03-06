{ config, lib, ... }:
let
  service = "affine";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
  dbPassword = "affine";
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
          extraOptions = [
            "--network=affine"
            "--health-cmd=pg_isready -U ${service} -d ${service}"
            "--health-interval=10s"
            "--health-timeout=5s"
            "--health-retries=5"
          ];
        };
        "${service}-redis" = {
          image = "redis:latest";
          extraOptions = [
            "--network=affine"
            "--health-cmd=redis-cli --raw incr ping"
            "--health-interval=10s"
            "--health-timeout=5s"
            "--health-retries=5"
          ];
        };
        ${service} = {
          image = "ghcr.io/toeverything/affine:stable";
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
            "127.0.0.1:3010:3010"
          ];
          dependsOn = [
            "${service}-postgres"
            "${service}-redis"
            "${service}-migration"
          ];
          extraOptions = [
            "--network=affine"
          ];
        };
        "${service}-migration" = {
          image = "ghcr.io/toeverything/affine:stable";
          volumes = [
            "${cfg.dataDir}/storage:/root/.affine/storage"
            "${cfg.dataDir}/config:/root/.affine/config"
          ];
          environment = {
            AFFINE_INDEXER_ENABLED = "false";
            REDIS_SERVER_HOST = "${service}-redis";
            DATABASE_URL = "postgresql://${service}:${dbPassword}@${service}-postgres:5432/${service}";
          };
          cmd = [ "sh" "-c" "node ./scripts/self-host-predeploy.js" ];
          dependsOn = [
            "${service}-postgres"
            "${service}-redis"
          ];
          extraOptions = [
            "--network=affine"
          ];
        };
      };
    };

    systemd.services."podman-create-affine-network" = {
      description = "Create podman network for AFFiNE";
      after = [ "podman.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/run/current-system/sw/bin/podman network create affine --ignore";
      };
    };

    systemd.services."podman-${service}-postgres".after = [ "podman-create-affine-network.service" ];
    systemd.services."podman-${service}-redis".after = [ "podman-create-affine-network.service" ];

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
