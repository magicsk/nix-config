{
  config,
  pkgs,
  ...
}:
let
  hl = config.homelab;
  wgKeyDir = "${hl.mounts.config}/wireguard";
  wgPrivateKeyPath = "${wgKeyDir}/private.key";
  wgPublicKeyPath = "${wgKeyDir}/public.key";
in
{
  persistence."/persist" = {
    directories = [
      { directory = wgKeyDir; user = "root"; group = "root"; mode = "0700"; }
    ];
  };
  systemd.services."generate-wireguard-keys" = {
    description = "Generate WireGuard keys if they do not exist";
    path = [ pkgs.wireguard-tools ];

    script = ''
      set -e # Exit immediately if a command exits with a non-zero status.
      if [ ! -f "${wgPrivateKeyPath}" ]; then
        echo "WireGuard private key not found. Generating new keys in ${wgKeyDir}..."
        # wg genkey outputs the private key to stdout
        wg genkey > ${wgPrivateKeyPath}
        chmod 600 ${wgPrivateKeyPath}

        # Derive the public key from the new private key
        cat ${wgPrivateKeyPath} | wg pubkey > ${wgPublicKeyPath}
        chmod 644 ${wgPublicKeyPath}
        echo "Successfully generated and stored WireGuard keys."
      else
        echo "WireGuard keys already exist at ${wgKeyDir}. No action taken."
      fi
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true; 
    };

    before = [ "network-pre.target" ];
    wantedBy = [ "multi-user.target" ];
  };
  networking = {
    wg-quick.interfaces.wg0 = {
      after = [ "generate-wireguard-keys.service" ];
      privateKeyFile = wgPrivateKeyPath;
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
