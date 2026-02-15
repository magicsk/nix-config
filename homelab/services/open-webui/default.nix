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
      host = "127.0.0.1";
      port = 8086;
      stateDir = cfg.dataDir;
      environment = {
        ENABLE_OLLAMA_API = "false";
        OPENAI_API_BASE_URLS = "http://127.0.0.1:8090/v1";
        OPENAI_API_KEYS = "";
      };
    };

    users.groups.${service} = {};
    users.users.${service} = {
      group = service;
      isSystemUser = true;
    };

    systemd.services.${service}.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = service;
      Group = service;
    };

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:8086
      '';
    };

    environment.persistence."/" = {
      directories = [
        { directory = cfg.dataDir; user = service; group = service; mode = "0755"; }
      ];
    };
  };
}
