{ config, lib, pkgs, ... }:
let
  service = "changedetection-io";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
  networkSubnet = "172.30.14.0/24";
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable changedetection.io";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/${service}";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "changedetection.${homelab.baseDomain}";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "changedetection.io";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Website change monitoring";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "sh-changedetection";
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
        "browser-chrome" = {
          image = "docker.io/selenium/standalone-chrome:4";
          autoStart = true;
          volumes = [
            "/dev/shm:/dev/shm"
          ];
          extraOptions = [
            "--network=${service}"
            "--hostname=browser-chrome"
          ];
          environment = {
            VNC_NO_PASSWORD = "1";
            SCREEN_WIDTH = "1920";
            SCREEN_HEIGHT = "1080";
            SCREEN_DEPTH = "24";
          };
        };

        ${service} = {
          image = "docker.io/dgtlmoon/changedetection.io:latest";
          autoStart = true;
          volumes = [
            "${cfg.dataDir}:/datastore"
          ];
          ports = [
            "127.0.0.1:${toString cfg.port}:5000"
          ];
          extraOptions = [ "--network=${service}" ];
          dependsOn = [ "browser-chrome" ];
          environment = {
            TZ = homelab.timeZone;
            BASE_URL = "https://${cfg.url}";
            USE_X_SETTINGS = "1";
            PORT = "5000";
            WEBDRIVER_URL = "http://browser-chrome:4444/wd/hub";
            PUID = toString config.users.users.${homelab.user}.uid;
            PGID = toString config.users.groups.${homelab.group}.gid;
          };
        };
      };
    };

    systemd.services."podman-network-${service}" = {
      description = "Create Podman network for ${service}";
      before = [
        "podman-${service}.service"
        "podman-browser-chrome.service"
      ];
      after = [ "podman.service" ];
      requiredBy = [
        "podman-${service}.service"
        "podman-browser-chrome.service"
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

    # changedetection.io fetches arbitrary public sites; route those checks over
    # the home connection instead of the WireGuard VPS path.
    networking.wg-quick.interfaces.wg0.postUp = ''
      ${pkgs.iproute2}/bin/ip rule add from ${networkSubnet} table main priority 86
    '';
    networking.wg-quick.interfaces.wg0.preDown = ''
      ${pkgs.iproute2}/bin/ip rule del from ${networkSubnet} table main priority 86 || true
    '';

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:${toString cfg.port}
      '';
    };

    environment.persistence."/".directories = [
      { directory = cfg.dataDir; user = homelab.user; group = homelab.group; mode = "0775"; }
    ];
  };
}
