{
  config,
  pkgs,
  ...
}:
{
  services.tailscale = {
    enable = true;
    authKeyFile = config.age.secrets.tailscaleAuthKey.path;
    extraUpFlags = [
      "--login-server=https://hs.magicsk.eu"
    ];
  };
}
