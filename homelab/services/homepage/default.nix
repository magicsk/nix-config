{
  config,
  lib,
  pkgs-unstable,
  ...
}:
let
  service = "homepage-dashboard";
  cfg = config.homelab.services.homepage;
  homelab = config.homelab;
in
{
  options.homelab.services.homepage = {
    enable = lib.mkEnableOption {
      description = "Enable ${service}";
    };
    network = lib.mkOption {
      default = [ ];
      type = lib.types.listOf (
        lib.types.attrsOf (
          lib.types.submodule {
            options = {
              description = lib.mkOption {
                type = lib.types.str;
              };
              href = lib.mkOption {
                type = lib.types.str;
              };
              siteMonitor = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Optional Homepage site monitor URL.";
              };
              icon = lib.mkOption {
                type = lib.types.str;
              };
            };
          }
        )
      );
    };
  };
  config = lib.mkIf cfg.enable {
    services.glances.enable = true;
    services.${service} = {
      enable = true;
      package = pkgs-unstable.homepage-dashboard;
      environmentFiles = [
        (builtins.toFile "homepage.env" "HOMEPAGE_ALLOWED_HOSTS=lab.${homelab.baseDomain}")
      ];
      settings = {
        layout = [
          {
            Glances = {
              header = false;
              style = "row";
              columns = 4;
            };
          }
          {
            Media = {
              header = true;
              style = "row";
              columns = 2;
            };
          }
          {
            Services = {
              header = true;
              style = "row";
              columns = 4;
            };
          }
          {
            "Smart Home" = {
              header = true;
              style = "row";
              columns = 3;
            };
          }
          {
            Network = {
              header = true;
              style = "row";
              columns = 3;
            };
          }
          {
            Sites = {
              header = true;
              style = "row";
              columns = 3;
            };
          }
          {
            Arr = {
              header = true;
              style = "row";
              columns = 3;
            };
          }
        ];
        headerStyle = "clean";
        statusStyle = "dot";
        hideVersion = "true";
        background = {
          image = "https://raw.githubusercontent.com/gethomepage/homepage/main/docs/assets/blossom_valley.jpg";
          opacity = 55;
        };
        cardBlur = "sm";
      };
      services =
        let
          homepageCategories = [
            "Arr"
            "Media"
            "Services"
            "Smart Home"
            "Sites"
            "Network"
          ];
          hl = config.homelab.services;
          homepageServices =
            x:
            (lib.attrsets.filterAttrs (
              name: value: value ? homepage && value.enable && value.homepage.category == x
            ) homelab.services);
          serviceEntry =
            x:
            let
              serviceCfg = hl.${x};
              homepageCfg = serviceCfg.homepage;
            in
            {
              "${homepageCfg.name}" =
                {
                  icon = homepageCfg.icon;
                  description = homepageCfg.description;
                  href = "https://${serviceCfg.url}";
                }
                // lib.optionalAttrs (homepageCfg.siteMonitor or true) {
                  siteMonitor = "https://${serviceCfg.url}";
                }
                // lib.optionalAttrs (homepageCfg ? widget && homepageCfg.widget != null) {
                  widget = homepageCfg.widget;
                }
                // lib.optionalAttrs (homepageCfg ? widgets && homepageCfg.widgets != null) {
                  widgets = homepageCfg.widgets;
                };
            };
          websiteServices =
            x:
            (lib.attrsets.filterAttrs (
              name: value:
              config.services.git-websites.enable && value.enable && value.homepage.category == x
            ) config.services.git-websites.sites);
          websiteEntry =
            x:
            let
              site = config.services.git-websites.sites.${x};
            in
            {
              "${site.homepage.name}" =
                {
                  icon = site.homepage.icon;
                  description = site.homepage.description;
                  href = "https://${site.host}";
                }
                // lib.optionalAttrs site.homepage.siteMonitor {
                  siteMonitor =
                    if site.homepage.siteMonitorUrl != null then
                      site.homepage.siteMonitorUrl
                    else
                      "https://${site.host}";
                }
                // lib.optionalAttrs (site.homepage.widget != null) {
                  widget = site.homepage.widget;
                }
                // lib.optionalAttrs (site.homepage.widgets != null) {
                  widgets = site.homepage.widgets;
                };
            };
          networkEntry =
            entry:
            lib.mapAttrs (_: value: lib.filterAttrs (_: fieldValue: fieldValue != null) value) entry;
          categoryExtra =
            cat:
            if cat == "Network" then
              map networkEntry cfg.network
            else
              [ ];
        in
        lib.lists.forEach homepageCategories (cat: {
          "${cat}" =
            lib.lists.forEach (lib.attrsets.mapAttrsToList (name: value: name) (homepageServices "${cat}"))
              serviceEntry
            ++ lib.lists.forEach (
              lib.attrsets.mapAttrsToList (name: value: name) (websiteServices "${cat}")
            ) websiteEntry
            ++ categoryExtra cat;
        })
        ++ [
          {
            Glances =
              let
                port = toString config.services.glances.port;
              in
              [
                {
                  Info = {
                    widget = {
                      type = "glances";
                      url = "http://localhost:${port}";
                      metric = "info";
                      chart = false;
                      version = 4;
                    };
                  };
                }
                {
                  "CPU Temp" = {
                    widget = {
                      type = "glances";
                      url = "http://localhost:${port}";
                      metric = "sensor:Package id 0";
                      chart = false;
                      version = 4;
                    };
                  };
                }
                {
                  Processes = {
                    widget = {
                      type = "glances";
                      url = "http://localhost:${port}";
                      metric = "process";
                      chart = false;
                      version = 4;
                    };
                  };
                }
                {
                  Network = {
                    widget = {
                      type = "glances";
                      url = "http://localhost:${port}";
                      metric = "network:enp2s0";
                      chart = false;
                      version = 4;
                    };
                  };
                }
              ];
          }
        ];
    };
    services.caddy.virtualHosts."lab.${homelab.baseDomain}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:${toString config.services.${service}.listenPort}
      '';
    };
  };
}
