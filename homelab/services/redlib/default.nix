{
  config,
  pkgs,
  lib,
  ...
}:
let
  service = "redlib";
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
      default = "redlib.${homelab.baseDomain}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "redlib";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Alternative front-end for reddit";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "redlib.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
    };
  };
  config = lib.mkIf cfg.enable {
    services.${service} = {
      enable = true;
      openFirewall = true;
      address = "127.0.0.1";
      port = 8282;
    };
    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:8282
      '';
    };
  };

}
