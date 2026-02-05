{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.services.backup;
  hl = config.homelab;
in
{
  options.homelab.services.backup = {
    enable = lib.mkEnableOption "BorgBackup service for mirroring selected folders with versioning";

    folders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${hl.mounts.Nitor}/Photos" ];
      description = "List of absolute paths on Nitor to backup to Alumentum";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of patterns to exclude from the main backup";
    };

    repoPath = lib.mkOption {
      type = lib.types.path;
      default = "${hl.mounts.Alumentum}/Backups";
      description = "Destination repository path for the main backup";
    };

    configBackup = {
      enable = lib.mkEnableOption "Backup of service configurations to Nitor";
      target = lib.mkOption {
        type = lib.types.path;
        default = "${hl.mounts.Nitor}/Backups/Services";
        description = "Where to store service config backups on Nitor";
      };
      exclude = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "List of patterns to exclude from the config backup";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.repoPath} 0775 ${hl.user} ${hl.group} -"
      "d ${cfg.configBackup.target} 0775 ${hl.user} ${hl.group} -"
    ];

    # Keep the built-in DB backup services alive if they are in use
    services.postgresqlBackup = {
      enable = config.services.postgresql.enable;
      databases = config.services.postgresql.ensureDatabases;
    };
    services.mysqlBackup = {
      enable = config.services.mysql.enable;
      databases = config.services.mysql.ensureDatabases;
    };

    services.borgbackup.jobs = {
      # Job 1: Configs -> Nitor
      services-to-nitor = lib.mkIf cfg.configBackup.enable {
        user = hl.user;
        group = hl.group;
        paths = [ hl.mounts.config ];
        repo = cfg.configBackup.target;
        exclude = cfg.configBackup.exclude;
        encryption.mode = "none";
        compression = "auto,zstd";
        startAt = "daily";
        doInit = true;
        preHook = ''
          if [ ! -d "${cfg.configBackup.target}/config" ]; then
            ${pkgs.borgbackup}/bin/borg init --encryption=none "${cfg.configBackup.target}" || true
          fi
          chown -R ${hl.user}:${hl.group} "${cfg.configBackup.target}" || true
        '';
        prune.keep = {
          daily = 7;
          weekly = 4;
        };
      };

      # Job 2: Nitor -> Alumentum
      nitor-to-alumentum = {
        user = hl.user;
        group = hl.group;
        paths = cfg.folders;
        repo = cfg.repoPath;
        exclude = cfg.exclude;
        encryption.mode = "none";
        compression = "auto,zstd";
        startAt = "daily";
        doInit = true;
        preHook = ''
          if [ ! -d "${cfg.repoPath}/config" ]; then
            ${pkgs.borgbackup}/bin/borg init --encryption=none "${cfg.repoPath}" || true
          fi
          chown -R ${hl.user}:${hl.group} "${cfg.repoPath}" || true
        '';
        prune.keep = {
          daily = 7;
          weekly = 4;
          monthly = 6;
        };
      };
    };
  };
}
