{
  config,
  lib,
  ...
}:
let
  service = "open-webui";
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
      default = "chat.${homelab.baseDomain}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Open WebUI";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "LLM Web Interface";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "open-webui.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
    };
  };

  config = lib.mkIf cfg.enable {
    services.${service} = {
      enable = true;
      host = "0.0.0.0";
      port = 8086;
      stateDir = cfg.dataDir;
      environment = {
        ENABLE_OLLAMA_API = "false";
        OPENAI_API_BASE_URLS = "http://127.0.0.1:8090/v1";
        OPENAI_API_KEYS = "";
        AIOHTTP_CLIENT_TIMEOUT = "600";
      }
      // lib.optionalAttrs config.homelab.services."codex-wrapper".enable {
        DEFAULT_MODELS = "gpt-5.6-sol:medium";
        DEFAULT_PINNED_MODELS = "gpt-5.6-sol:medium,gpt-5.6-terra:medium,gpt-5.6-luna:medium";
      };
    };

    users.groups.${service} = { };
    users.users.${service} = {
      group = service;
      isSystemUser = true;
    };

    systemd.services.${service} = {
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = service;
        Group = service;
        # Startup performs a blocking remote fetch before binding the web port.
        # Prefer working IPv4 instead of waiting on the host's black-holed IPv6.
        RestrictAddressFamilies = lib.mkForce [
          "AF_INET"
          "AF_UNIX"
        ];
      };
    }
    // lib.optionalAttrs config.homelab.services."codex-wrapper".enable {
      wants = [ "codex-wrapper.service" ];
      after = [ "codex-wrapper.service" ];
    };

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://${config.services.${service}.host}:${toString config.services.${service}.port}
      '';
    };

    environment.persistence."/" = {
      directories = [
        {
          directory = cfg.dataDir;
          user = service;
          group = service;
          mode = "0755";
        }
      ];
    };
  };
}
