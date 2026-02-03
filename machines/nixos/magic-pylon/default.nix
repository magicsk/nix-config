{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  hl = config.homelab;
  hardDrives = [
    "/dev/disk/by-uuid/8c78faa7-c01b-4847-a9ed-5c2c9d500868" # Alumentum
    "/dev/disk/by-uuid/a85d790f-f428-4be9-ac0f-e40ff7b6f575" # Nitor
  ];
in
{
  nixpkgs.overlays = [
    (final: prev: {
      vaapiIntel = prev.vaapiIntel.override { enableHybridCodec = true; };
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (python-final: python-prev: {
          psycopg = python-prev.psycopg.overridePythonAttrs (oldAttrs: {
            doCheck = false;
            pythonImportsCheck = [ "psycopg" "psycopg_c" ];
          });
        })
      ];
    })
  ];
  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        intel-vaapi-driver
        vaapiVdpau
        intel-compute-runtime
        vpl-gpu-rt
      ];
    };
  };

  programs.fuse.userAllowOther = true;
  
  boot = {
    kernelParams = [
      "pcie_aspm=force"
      "consoleblank=60"
      "acpi_enforce_resources=lax"
    ];
    kernelModules = [
      "kvm-intel"
      "coretemp"
      "jc42"
      "lm78"
    ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod" ];
  };

  imports = [
    ./homelab
    ./filesystems
    ./secrets
    ./network
  ];

  systemd.services.hd-idle = {
    description = "External HD spin down daemon";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart =
        let
          idleTime = toString 900;
          hardDriveParameter = lib.strings.concatMapStringsSep " " (x: "-a ${x} -i ${idleTime}") hardDrives;
        in
        "${pkgs.hd-idle}/bin/hd-idle -i 0 ${hardDriveParameter}";
    };
  };

/*   services.hddfancontrol = {
    enable = true;
    settings = {
      harddrives = {
        disks = hardDrives;
        pwmPaths = [ "/sys/class/hwmon/hwmon2/device/pwm2:50:50" ];
        extraArgs = [
          "-i 30sec"
        ];
      };
    };
  }; */

  virtualisation.docker.storageDriver = "overlay2";

  system.autoUpgrade.enable = true;

/*   services.mover = {
    enable = true;
    cacheArray = hl.mounts.fast;
    backingArray = hl.mounts.slow;
    user = hl.user;
    group = hl.group;
    percentageFree = 60;
    excludedPaths = [
      "Media/Music"
      "Media/Photos"
      "YoutubeCurrent"
      "Downloads.tmp"
      "Media/Kiwix"
      "Documents"
      "TimeMachine"
      ".DS_Store"
      ".cache"
    ];
  }; */

  services.autoaspm.enable = true;
  powerManagement.powertop.enable = true;

  environment.systemPackages = with pkgs; [
    pciutils
    glances
    hdparm
    hd-idle
    hddtemp
    smartmontools
    cpufrequtils
    intel-gpu-tools
    powertop
    btop
    gptfdisk
    xfsprogs
    parted
    btrfs-progs
    wireguard-tools
    dua
    unzip
  ];

/*   tg-notify = {
    enable = true;
    credentialsFile = config.age.secrets.tgNotifyCredentials.path;
  }; */
}
