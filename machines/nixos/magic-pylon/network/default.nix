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
      enable = true;
      allowPing = true;
      trustedInterfaces = [ "enp2s0" "enp3s0" "enp4s0" ];
    };

    wg-quick.interfaces.wg0 = {
      privateKeyFile = config.age.secrets.wg0-private-key.path;
      address = [ "10.0.0.2/32" ];

      peers = [
        {
          publicKey = "mJy1oJ7htHL/oGSJfGs6QhZG59wiqMj//CG0Xyh8MHY=";
          endpoint = "132.226.217.72:51820";
          allowedIPs = [ "0.0.0.0/0" ];
          persistentKeepalive = 25;
        }
      ];
    };
  };
}
