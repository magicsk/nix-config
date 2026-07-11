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
    ./tailscale.nix
  ];
  networking = {
    useDHCP = false;
    networkmanager.enable = false;
    hostName = "magic-pylon";
    
    bridges.br0 = {
      interfaces = [ "enp1s0" "enp2s0" "enp3s0" "enp4s0" ];
    };
    
    interfaces.br0 = {
      useDHCP = true;
      ipv6.addresses = [
        {
          address = "2a01:c846:3901:9301::a";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway6 = {
      address = "fe80::921b:eff:febf:7819";
      interface = "br0";
    };
    
    firewall = {
      enable = false;
      allowPing = true;
      trustedInterfaces = [ "enp2s0" "enp3s0" "enp4s0" ];
    };
  };
}
