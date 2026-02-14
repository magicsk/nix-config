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
    name = lib.mkOption {
      type = lib.types.str;
      default = "vanilla";
    };
    enable = lib.mkEnableOption {
      description = "Enable Minecraft Server";
    };
    configDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/minecraft";
    };
    startCommand = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.jdk17}/bin/java @user_jvm_args.txt @libraries/net/minecraftforge/forge/1.20.1-47.4.10/unix_args.txt nogui \"$@\"";
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
        { directory = "${cfg.configDir}/${cfg.name}"; user = "minecraft"; group = "minecraft"; mode = "0755"; }
      ];
    };

    systemd.services."minecraft-${cfg.name}" = {
      enable = cfg.enable;
      description = "Forge Minecraft Server";
      serviceConfig = {
        ExecStart = cfg.startCommand;
        WorkingDirectory = "${cfg.configDir}/${cfg.name}";
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
