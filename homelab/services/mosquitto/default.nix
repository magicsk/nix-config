{
  config,
  pkgs,
  lib,
  ...
}:
let
  service = "mosquitto";
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
      default = "${service}.${homelab.baseDomain}";
    };
  };
  config = lib.mkIf cfg.enable {
    services.${service} = {
      enable = true;
      dataDir = cfg.dataDir;
      listeners = [
        {
          acl = [ "pattern readwrite #" ];
          omitPasswordAuth = true;
          settings.allow_anonymous = true;
        }
      ];
    };
    environment.persistence."/".directories = [
      { directory = cfg.dataDir; user = homelab.user; group = homelab.group; mode = "0777"; }
    ];
  };

}
