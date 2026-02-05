{ config, lib, ... }:
let
  homelab = config.homelab;
  dataDir = "${homelab.mounts.config}/postgresql/${config.services.postgresql.package.psqlSchema}";
in
{
  config = lib.mkIf config.services.postgresql.enable {
    services.postgresql = {
      inherit dataDir;
    };

    systemd.services.postgresql.serviceConfig = {
      ReadWritePaths = [ dataDir ];
    };

    environment.persistence."/".directories = [
      {
        directory = dataDir;
        user = "postgres";
        group = "postgres";
        mode = "0700";
      }
    ];
  };
}
