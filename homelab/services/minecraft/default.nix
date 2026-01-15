{ 
  config,
  pkgs,
  lib,
  ... 
}:
let
  homelab = config.homelab;
  cfg = config.homelab.services.minecraft;
in
{
  options.homelab.services.minecraft = {
    enable = lib.mkEnableOption {
      description = "Enable Minecraft Server";
    };
    configDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/minecraft";
    };
  };
  config = lib.mkIf cfg.enable {
    users = {
      groups.minecraft = {};
      extraUsers.minecraft = {
        isSystemUser = true;
        group = "minecraft";
        home = cfg.configDir;
        createHome = true;
        packages = [
          pkgs.jdk17
        ];
      };
    };
    environment.persistence."/" = {
      directories = [
        { directory = cfg.configDir; user = "minecraft"; group = "minecraft"; mode = "0755"; }
      ];
    };

    systemd.services.minecraft = {
      enable = cfg.enable;
      description = "Forge Minecraft Server";
      serviceConfig = {
        ExecStart = "${pkgs.jdk17}/bin/java @user_jvm_args.txt @libraries/net/minecraftforge/forge/1.20.1-47.4.0/unix_args.txt nogui \"$@\"";
        WorkingDirectory = cfg.configDir;
        Restart = "always";
        RestartSec = 10;
      };
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
    };

    networking.firewall.allowedTCPPorts = [ 25565 25575 ];
    networking.firewall.allowedUDPPorts = [ 25565 ];
  };
}
