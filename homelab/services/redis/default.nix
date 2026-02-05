{ config, lib, ... }:
let
  homelab = config.homelab;
in
{
  config = {
    services.redis.servers."" = {
      enable = true;
      bind = "0.0.0.0";
      port = 6379;
    };
  };
}
