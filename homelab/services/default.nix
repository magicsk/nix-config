{
  config,
  lib,
  pkgs,
  ...
}:
let
  hl = config.homelab.services;
  portClaim = name: port: enabled: { inherit name port enabled; };
  reservedPortClaims =
    map (claim: {
      inherit (claim) name port;
      enabled = true;
    }) hl.reservedPorts;
  enabledPortClaims =
    reservedPortClaims
    ++
    lib.filter (claim: claim.enabled) [
      (portClaim "affine" 3010 hl.affine.enable)
      (portClaim "borg-ui" 8084 hl."borg-ui".enable)
      (portClaim "bugsink" hl.bugsink.port hl.bugsink.enable)
      (portClaim "changedetection-io" hl."changedetection-io".port hl."changedetection-io".enable)
      (portClaim "claude-wrapper" 8090 hl."claude-wrapper".enable)
      (portClaim "code-server" 8443 hl."code-server".enable)
      (portClaim "esphome" config.services.esphome.port hl.esphome.enable)
      (portClaim "flaresolverr" 8191 hl.flaresolverr.enable)
      (portClaim "go2rtc-http" 1984 hl.go2rtc.enable)
      (portClaim "go2rtc-webrtc" 8555 hl.go2rtc.enable)
      (portClaim "homeassistant" 8123 hl.homeassistant.enable)
      (portClaim "html2rss-web" hl."html2rss-web".port hl."html2rss-web".enable)
      (portClaim "homepage" config.services."homepage-dashboard".listenPort hl.homepage.enable)
      (portClaim "immich" config.services.immich.port hl.immich.enable)
      (portClaim "jellyfin" 8096 hl.jellyfin.enable)
      (portClaim "jellyseerr" hl.jellyseerr.port hl.jellyseerr.enable)
      (portClaim "matter-server" 5580 hl."matter-server".enable)
      (portClaim "minecraft" 25565 hl.minecraft.enable)
      (portClaim "minecraft-rcon" 25575 hl.minecraft.enable)
      (portClaim "mosquitto" 1883 hl.mosquitto.enable)
      (portClaim "obico-ml" 3333 hl."obico-ml".enable)
      (portClaim "open-webui" config.services."open-webui".port hl."open-webui".enable)
      (portClaim "paperless" 8000 hl.paperless.enable)
      (portClaim "plausible" hl.plausible.port hl.plausible.enable)
      (portClaim "plausible-clickhouse" hl.plausible.clickhouseHttpPort hl.plausible.enable)
      (portClaim "prowlarr" 9696 hl.prowlarr.enable)
      (portClaim "qbittorrent" 8112 hl.qbittorrent.enable)
      (portClaim "radarr" 7878 hl.radarr.enable)
      (portClaim "redlib" hl.redlib.port hl.redlib.enable)
      (portClaim "sonarr" 8989 hl.sonarr.enable)
      (portClaim "vaultwarden" 8222 hl.vaultwarden.enable)
      (portClaim "zigbee2mqtt" 8181 hl.zigbee2mqtt.enable)
    ];
  claimedPorts = lib.unique (map (claim: claim.port) enabledPortClaims);
  claimsForPort = port: lib.filter (claim: claim.port == port) enabledPortClaims;
  duplicatePorts = lib.filter (port: lib.length (claimsForPort port) > 1) claimedPorts;
  formatDuplicate =
    port:
    "${toString port} (${lib.concatStringsSep ", " (map (claim: claim.name) (claimsForPort port))})";
in
{
  options.homelab.services = {
    enable = lib.mkEnableOption "Settings and services for the homelab";
    reservedPorts = lib.mkOption {
      default = [ ];
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
            };
            port = lib.mkOption {
              type = lib.types.port;
            };
          };
        }
      );
      description = "Host TCP ports that are reserved by services outside this homelab module.";
    };
  };

  config = lib.mkIf config.homelab.services.enable {
    assertions = [
      {
        assertion = duplicatePorts == [ ];
        message = "Homelab service port collision(s): ${lib.concatStringsSep "; " (map formatDuplicate duplicatePorts)}";
      }
    ];
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
    security.acme = {
      acceptTerms = true;
      defaults.email = "minemagicsk@gmail.com";
      certs.${config.homelab.baseDomain} = {
        reloadServices = [ "caddy.service" ];
        domain = "${config.homelab.baseDomain}";
        extraDomainNames = [ "*.${config.homelab.baseDomain}" ];
        dnsProvider = "cloudflare";
        dnsResolver = "1.1.1.1:53";
        dnsPropagationCheck = true;
        group = config.services.caddy.group;
        environmentFile = config.homelab.cloudflare.dnsCredentialsFile;
      };
    };
    services.caddy = {
      enable = true;
      globalConfig = ''
        auto_https off
      '';
      virtualHosts = {
        "http://${config.homelab.baseDomain}" = {
          extraConfig = ''
            redir https://{host}{uri}
          '';
        };
        "http://*.${config.homelab.baseDomain}" = {
          extraConfig = ''
            redir https://{host}{uri}
          '';
        };

      };
    };
    nixpkgs.config.permittedInsecurePackages = [
      "dotnet-sdk-6.0.428"
      "aspnetcore-runtime-6.0.36"
      "python3.12-ecdsa-0.19.1"
    ];
    virtualisation.podman = {
      dockerCompat = true;
      autoPrune.enable = true;
      defaultNetwork.settings = {
        dns_enabled = true;
      };
    };
    virtualisation.oci-containers = {
      backend = "podman";
    };

    networking.firewall.interfaces.podman0.allowedUDPPorts =
      lib.lists.optionals config.virtualisation.podman.enable
        [ 53 ];
  };

  imports = [
    ./affine
    ./arr/prowlarr
    # ./arr/bazarr
    ./arr/jellyseerr
    ./arr/sonarr
    ./arr/radarr
    #./arr/lidarr
    # ./audiobookshelf
    ./backup
    ./borg-ui
    ./bugsink
    ./changedetection-io
    ./claude-wrapper
    ./code-server
    ./esphome
    ./flaresolverr
    ./go2rtc
    ./headscale
    ./homeassistant
    ./html2rss-web
    ./homepage
    ./immich
    ./jellyfin
    ./matter-server
    ./minecraft
    ./mosquitto
    ./nextcloud
    ./obico-ml
    ./open-webui
    ./otbr
    ./paperless-ngx
    ./plausible
    ./postgresql
    ./qbittorrent
    ./redlib
    ./redis
    ./stalwart
    ./trakt-backup
    # ./uptime-kuma
    ./vaultwarden
    ./websites
    ./zigbee2mqtt
  ];
}
