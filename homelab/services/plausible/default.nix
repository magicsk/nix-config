{ config, lib, ... }:
let
  service = "plausible";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable ${service}";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "${service}.${homelab.baseDomain}";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8019;
    };
    secretKeybaseFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a file containing 64 hex characters (openssl rand -hex 32)";
    };
    adminEmail = lib.mkOption {
      type = lib.types.str;
      default = "minemagicsk@gmail.com";
    };
    adminName = lib.mkOption {
      type = lib.types.str;
      default = "admin";
    };
    adminPasswordFile = lib.mkOption {
      type = lib.types.path;
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Plausible";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Privacy-friendly web analytics";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "plausible.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
    };
  };

  config = lib.mkIf cfg.enable {
    services.${service} = {
      enable = true;
      server = {
        baseUrl = "https://${cfg.url}";
        port = cfg.port;
        secretKeybaseFile = cfg.secretKeybaseFile;
      };
      adminUser = {
        email = cfg.adminEmail;
        name = cfg.adminName;
        passwordFile = cfg.adminPasswordFile;
        activate = true;
      };
    };

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:${toString cfg.port}
      '';
    };

    environment.persistence."/".directories = [
      {
        directory = "/var/lib/clickhouse";
        user = "clickhouse";
        group = "clickhouse";
        mode = "0700";
      }
    ];
  };
}
