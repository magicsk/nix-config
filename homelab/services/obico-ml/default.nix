{ config, lib, ... }:
let
  service = "obico-ml";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable ${service}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Obico ML";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "3D print spaghetti detection";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "obico.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Smart Home";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation = {
      podman.enable = true;
      oci-containers.containers.${service} = {
        image = "nberk/ha_bambu_lab_p1_spaghetti_detection_standalone:latest";
        ports = [
          "3333:3333"
        ];
        environment = {
          ML_API_TOKEN = "obico_api_secret";
        };
      };
    };
  };
}
