{
  config,
  lib,
  pkgs,
  ...
}:
let
  hl = config.homelab;
  cfg = hl.samba;
in
{
  options.homelab.samba = {
    enable = lib.mkEnableOption {
      description = "Samba shares for the homelab";
    };
    example = lib.mkOption {
      default = lib.attrsets.mapAttrs (
        name: value: name:
        value.settings
      ) cfg.shares;
    };
    passwordFile = lib.mkOption {
      type = lib.types.path;
      default = /dev/null;
      description = "Path to samba password file";
    };
    globalSettings = lib.mkOption {
      description = "Global Samba parameters";
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "browseable" = "yes";
        "writeable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
      };
    };
    commonSettings = lib.mkOption {
      description = "Parameters applied to each share";
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "security" = "user";
        "invalid users" = [ "root" ];
      };
      apply =
        old:
        lib.attrsets.mergeAttrsList [
          {
            "preserve case" = "yes";
            "short preserve case" = "yes";
            "browseable" = "yes";
            "writeable" = "yes";
            "read only" = "no";
            "guest ok" = "no";
            "create mask" = "0644";
            "directory mask" = "0755";
            "valid users" = hl.user;
          }
          old
        ];
    };
    shares = lib.mkOption {
      type = lib.types.attrs;
      example = lib.literalExpression ''
        CoolShare = {
          path = "/mnt/CoolShare";
          "fruit:aapl" = "yes";
        };
      '';
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    services.samba-wsdd.enable = true; # make shares visible for windows 10 clients

    environment.systemPackages = [ config.services.samba.package ];

    systemd.tmpfiles.rules = map (x: "d ${x.path} 0775 ${hl.user} ${hl.group} - -") (
      lib.attrValues cfg.shares
    );

    system.activationScripts.samba_user_create = ''
      smb_password=$(cat "${config.age.secrets.sambaPassword.path}")
      echo -e "$smb_password\n$smb_password\n" | ${lib.getExe' pkgs.samba "smbpasswd"} -a -s ${hl.user}
    '';

    networking.firewall = {
      allowedTCPPorts = [ 5357 ];
      allowedUDPPorts = [ 3702 ];
    };

    services.samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = lib.mkMerge [
          {
            workgroup = lib.mkDefault "WORKGROUP";
            "server string" = lib.mkDefault config.networking.hostName;
            "netbios name" = lib.mkDefault config.networking.hostName;
            "security" = lib.mkDefault "user";
            "invalid users" = [ "root" ];
            "guest account" = lib.mkDefault "nobody";
            "map to guest" = lib.mkDefault "bad user";
            "passdb backend" = lib.mkDefault "tdbsam";
            "vfs objects" = "catia fruit streams_xattr";
            "fruit:metadata" = "stream";
            "fruit:model" = "MacPro7,1@ECOLOR=226,226,224";
            "fruit:posix_rename" = "yes ";
            "fruit:veto_appledouble" = "no";
            "fruit:wipe_intentionally_left_blank_rfork" = "yes";
            "fruit:delete_empty_adfiles" = "yes";
            "fruit:advertise_fullsync" = "true";
            "fruit:aapl" = "yes";
            "fruit:copyfile" = "yes";
            "fruit:zero_file_id" = "yes";
            "fruit:nfs_aces" = "no";
            "acl allow execute always" = "True";
            "msdfs root" = "no";
            "allow insecure wide links" = "yes";
          }
          cfg.globalSettings
        ];
      } // builtins.mapAttrs (name: value: value // cfg.commonSettings) cfg.shares;
    };
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        domain = true;
        hinfo = true;
        userServices = true;
        workstation = true;
      };
      extraServiceFiles = {
        smb = ''
          <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
          <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
          <service-group>
          <name replace-wildcards="yes">%h</name>
          <service>
          <type>_smb._tcp</type>
          <port>445</port>
          </service>
          </service-group>
        '';
      };
    };
  };
}
