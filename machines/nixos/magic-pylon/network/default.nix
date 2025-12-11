{
  config,
  pkgs,
  ...
}:
let
  hl = config.homelab;
in
{
  imports = [
    ./wireguard.nix
  ];
  networking = {
    useDHCP = false;
    networkmanager.enable = false;
    hostName = "magic-pylon";
    
    bridges.br0 = {
      interfaces = [ "enp1s0" "enp2s0" "enp3s0" "enp4s0" ];
    };
    
    interfaces.br0.useDHCP = true;
    
    firewall = {
      enable = false;
      allowPing = true;
      trustedInterfaces = [ "enp2s0" "enp3s0" "enp4s0" ];
    };
  };
}
