{ config, lib, ... }:
let
  homelab = config.homelab;
  cfg = config.homelab.services.code-server;
in
{
  options.homelab.services.code-server = {
    enable = lib.mkEnableOption {
      description = "Enable code-server";
    };
    configDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/code-server";
    };
    passFile = lib.mkOption {
      type = lib.types.path;
    };
    passSudoFile = lib.mkOption {
      type = lib.types.path;
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "code.${homelab.baseDomain}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Code";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Web-based code editor";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "coder.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [ "d ${cfg.configDir} 0775 ${homelab.user} ${homelab.group} - -" ];
    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:8443
      '';
    };
    virtualisation = {
      podman.enable = true;
      oci-containers = {
        containers = {
          code-server = {
            image = "linuxserver/code-server:latest";
            autoStart = true;
            extraOptions = [
              "--pull=newer"
              "--env-file=/run/agenix/code-server.env"
            ];
            volumes = [
              "${cfg.configDir}:/config"
              "${homelab.mounts.Wilson}/Developer:/Developer"
            ];
            ports = [
              "127.0.0.1:8443:8443"
            ];
            environment = {
              TZ = homelab.timeZone;
              PUID = toString config.users.users.${homelab.user}.uid;
              PGID = toString config.users.groups.${homelab.group}.gid;
              PROXY_DOMAIN = cfg.url;
              DEFAULT_WORKSPACE = "/Developer";
              PWA_APPNAME = "Code";
            };
          };
        };
      };
    };

    systemd.services."podman-code-server" = {
      preStart = ''
        mkdir -p /run/agenix
        echo "PASSWORD=$(cat ${cfg.passFile})" > /run/agenix/code-server.env
        echo "SUDO_PASSWORD=$(cat ${cfg.passSudoFile})" >> /run/agenix/code-server.env
        chmod 600 /run/agenix/code-server.env
      '';
    };
  };
}
