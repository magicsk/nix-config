{ config, lib, pkgs, ... }:
let
  service = "go2rtc";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
  configFile = pkgs.writeText "go2rtc.yaml" ''
    streams:
      usb_cam: exec:ffmpeg -f v4l2 -input_format mjpeg -video_size 1920x1080 -framerate 30 -i /dev/v4l/by-id/usb-2M_UVC_CAMERA_NexiGo_N60_FHD_Webcam_2021030103-video-index0 -c:v libx264 -preset ultrafast -tune zerolatency -g 30 -f rtsp {output}
  '';
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable ${service}";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "${service}.${homelab.baseDomain}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "go2rtc";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Camera streaming";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "sh-go2rtc.svg";
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
        image = "alexxit/go2rtc";
        volumes = [
          "${configFile}:/config/go2rtc.yaml:ro"
          "/dev:/dev"
        ];
        extraOptions = [
          "--device-cgroup-rule=c 81:* rmw" # video4linux
          "--group-add=video"
          "--network=host"
        ];
        environment = {
          TZ = homelab.timeZone;
        };
      };
    };

    # host networking exposes ports directly, open for LAN access
    networking.firewall.allowedTCPPorts = [ 1984 8555 ];
    networking.firewall.allowedUDPPorts = [ 8555 ];

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:1984
      '';
    };

  };
}
