{ config, lib, ... }:
let
  service = "claude-wrapper";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
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
      default = "claude-api.${homelab.baseDomain}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Claude API";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "OpenAI-compatible Claude API wrapper";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "claude.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
    };
    ghcrTokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing a GitHub PAT with read:packages scope";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation = {
      podman.enable = true;
      oci-containers.containers.${service} = {
        image = "ghcr.io/magicsk/claude-code-openai-wrapper:latest";
        autoStart = true;
        extraOptions = [
          "--pull=newer"
        ];
        volumes = [
          "${cfg.dataDir}/workspace:/workspace"
          "${cfg.dataDir}/.claude:/home/claude/.claude"
        ];
        ports = [
          "127.0.0.1:8090:8000"
        ];
        environment = {
          TZ = homelab.timeZone;
          CLAUDE_CWD = "/workspace";
          DEFAULT_MODEL = "claude-sonnet-4-5-20250929";
        };
      };
    };

    systemd.services."podman-${service}" = {
      preStart = ''
        cat ${cfg.ghcrTokenFile} | podman login ghcr.io -u magicsk --password-stdin
      '';
    };

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:8090
      '';
    };

    environment.persistence."/" = {
      directories = [
        { directory = "${cfg.dataDir}/workspace"; user = homelab.user; group = homelab.group; mode = "0755"; }
        { directory = "${cfg.dataDir}/.claude"; user = homelab.user; group = homelab.group; mode = "0755"; }
      ];
    };
  };
}
