{ lib, config, ... }:
let
  cfg = config.homelab;
in
{
  options.homelab = {
    enable = lib.mkEnableOption "The homelab services and configuration variables";
    mounts.config = lib.mkOption {
      default = "/persist/opt/services";
      type = lib.types.path;
      description = ''
        Path to the service configuration files
      '';
    };
    mounts.Alumentum = lib.mkOption {
      default = "/mnt/Alumentum";
      type = lib.types.path;
      description = ''
        Path to the Alumentum (HDD 1TB)
      '';
    };
    mounts.Nitor = lib.mkOption {
      default = "/mnt/Nitor";
      type = lib.types.path;
      description = ''
        Path to the Nitor (2x HDD RAID0 6TB)
      '';
    };
    mounts.Wilson = lib.mkOption {
      default = "/mnt/Wilson";
      type = lib.types.path;
      description = ''
        Path to the Wilson (SSD 2TB, subvolume on system disk)
      '';
    };
    mounts.Tallow = lib.mkOption {
      default = "/mnt/Tallow";
      type = lib.types.path;
      description = ''
        Path to the Tallow (SSD 256GB)
      '';
    };
    user = lib.mkOption {
      default = "share";
      type = lib.types.str;
      description = ''
        User to run the homelab services as
      '';
      #apply = old: builtins.toString config.users.users."${old}".uid;
    };
    group = lib.mkOption {
      default = "share";
      type = lib.types.str;
      description = ''
        Group to run the homelab services as
      '';
      #apply = old: builtins.toString config.users.groups."${old}".gid;
    };
    timeZone = lib.mkOption {
      default = "Europe/Bratislava";
      type = lib.types.str;
      description = ''
        Time zone to be used for the homelab services
      '';
    };
    baseDomain = lib.mkOption {
      default = "magicsk.eu";
      type = lib.types.str;
      description = ''
        Base domain name to be used to access the homelab services via Caddy reverse proxy
      '';
    };
    cloudflare.dnsCredentialsFile = lib.mkOption {
      type = lib.types.path;
    };
  };
  imports = [
    ./services
    ./samba
    # ./networks
    ./motd
  ];
  config = lib.mkIf cfg.enable {
    users = {
      groups.${cfg.group} = {
        gid = 993;
      };
      users.${cfg.user} = {
        uid = 994;
        isSystemUser = true;
        group = cfg.group;
      };
    };
  };
}
