{
  config,
  pkgs,
  ...
}:
let
  hl = config.homelab;
in
{
  systemd.tmpfiles.rules = [
    "d /mnt/Wilson 0755 root root -"
    "d /mnt/Alumentum 0755 root root -"
    "d /mnt/Nitor 0755 root root -"
    "d /mnt/Tallow 0755 root root -"
  ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/caa3ae9c-92aa-4a2a-b4b4-06ac762cd838";
      fsType = "btrfs";
      options = [ "subvol=root" "compress=zstd" ];
      neededForBoot = true;
    };
    
  fileSystems."/nix" =
    { device = "/dev/disk/by-uuid/caa3ae9c-92aa-4a2a-b4b4-06ac762cd838";
      fsType = "btrfs";
      options = [ "subvol=nix" "compress=zstd" ];
      neededForBoot = true;
    };

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/caa3ae9c-92aa-4a2a-b4b4-06ac762cd838";
      fsType = "btrfs";
      options = [ "subvol=home" "compress=zstd" "noatime" "space_cache=v2" ];
      neededForBoot = true;
    };

  fileSystems."/mnt/Wilson" =
    { device = "/dev/disk/by-uuid/caa3ae9c-92aa-4a2a-b4b4-06ac762cd838";
      fsType = "btrfs";
      options = [ "subvol=persistant" "compress=zstd:2" "noatime" "space_cache=v2" ];
    };
    
  fileSystems."/mnt/Alumentum" =
    { device = "/dev/disk/by-uuid/8c78faa7-c01b-4847-a9ed-5c2c9d500868";
      fsType = "btrfs";
      options = [ "compress=zstd:2" "noatime" "space_cache=v2" ];
    };

  fileSystems."/mnt/Nitor" =
    { device = "/dev/disk/by-uuid/a85d790f-f428-4be9-ac0f-e40ff7b6f575";
      fsType = "btrfs";
      options = [ "compress=zstd:2" "noatime" "space_cache=v2" ];
    };

  fileSystems."/mnt/Tallow" =
    { device = "/dev/disk/by-uuid/44a1228a-8cca-4a89-9114-fd59fa830e29";
      fsType = "btrfs";
      options = [ "compress=zstd:2" "noatime" "space_cache=v2" ];
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/70C2-0726";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
      neededForBoot = true;
    };

  fileSystems."/swap" =
    { device = "/dev/disk/by-uuid/caa3ae9c-92aa-4a2a-b4b4-06ac762cd838";
      fsType = "btrfs";
      options = [ "subvol=swap" "noatime" ];
      neededForBoot = true;
    };

  swapDevices = [ { device = "/swap/swapfile"; } ];

  zramSwap.enable = true;

  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
  };

  # services.smartd = {
  #   enable = true;
  #   defaults.autodetected = "-a -o on -S on -s (S/../.././02|L/../../6/03) -n standby,q";
  #   notifications = {
  #     wall = {
  #       enable = true;
  #     };
  #     mail = {
  #       enable = true;
  #       sender = config.email.fromAddress;
  #       recipient = config.email.toAddress;
  #     };
  #   };
  # };

}
