{ config, lib, ... }:
let
  homelab = config.homelab;
  dataDir = "${homelab.mounts.config}/postgresql/${config.services.postgresql.package.psqlSchema}";
  backupDir = "${homelab.mounts.Nitor}/Backups/postgresql";
in
{
  config = lib.mkIf config.services.postgresql.enable {
    services.postgresql = {
      inherit dataDir;
    };

    services.postgresqlBackup = {
      enable = true;
      databases = config.services.postgresql.ensureDatabases;
      location = backupDir;
    };

    systemd.services.postgresql.serviceConfig = {
      ReadWritePaths = [ dataDir ];
    };

    systemd.tmpfiles.rules = [
      "d ${backupDir} 0700 postgres postgres -"
    ];

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
