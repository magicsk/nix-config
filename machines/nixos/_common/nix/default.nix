{ lib, ... }:
{
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.optimise.automatic = true;
  nix.optimise.dates = [ "weekly" ];

  nix.settings = {
    download-buffer-size = 134217728;
    experimental-features = lib.mkDefault [
      "nix-command"
      "flakes"
      "auto-allocate-uids"
      "cgroups"
    ];
    cores = 0;
    max-jobs = "auto";
    auto-optimise-store = true;
  };

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };
}
