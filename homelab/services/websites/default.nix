{ config, lib, ... }:
let
  cfg = config.homelab.services.websites;
in
{
  options.homelab.services.websites.enable = lib.mkEnableOption "Git-deployed websites";

  config = lib.mkIf cfg.enable {
    services.git-websites.enable = true;

    systemd.tmpfiles.rules = [
      "d ${config.homelab.mounts.config}/websites 0755 ${config.homelab.user} ${config.homelab.group} - -"
    ];

    environment.persistence."/".directories = [
      {
        directory = "${config.homelab.mounts.config}/websites";
        user = config.homelab.user;
        group = config.homelab.group;
        mode = "0755";
      }
    ];
  };

  imports = [
    ./api
    ./maxmiedinger
    ./reciper
    ./startpage
    ./transi-eu
  ];
}
