{
  config,
  lib,
  pkgs,
  ...
}:
let
  service = "monitoring";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
  grafanaDataDir = config.services.grafana.dataDir;
  lokiDataDir = config.services.loki.dataDir;
  hostedServices = [
    {
      name = "Home Assistant";
      unit = "podman-homeassistant.service";
    }
    {
      name = "Remux";
      unit = "podman-remux.service";
    }
    {
      name = "CrossWatch";
      unit = "podman-crosswatch.service";
    }
    {
      name = "Immich";
      unit = "immich-server.service";
    }
    {
      name = "Nextcloud";
      unit = "phpfpm-nextcloud.service";
    }
    {
      name = "Paperless-ngx";
      unit = "podman-paperless.service";
    }
    {
      name = "Open WebUI";
      unit = "open-webui.service";
    }
    {
      name = "Vaultwarden";
      unit = "vaultwarden.service";
    }
    {
      name = "AFFiNE";
      unit = "podman-affine.service";
    }
    {
      name = "qBittorrent";
      unit = "qbittorrent.service";
    }
    {
      name = "Sonarr";
      unit = "sonarr.service";
    }
    {
      name = "Radarr";
      unit = "radarr.service";
    }
    {
      name = "Prowlarr";
      unit = "prowlarr.service";
    }
    {
      name = "Borg-UI";
      unit = "podman-borg-ui.service";
    }
    {
      name = "Bugsink";
      unit = "podman-bugsink.service";
    }
    {
      name = "changedetection.io";
      unit = "podman-changedetection-io.service";
    }
    {
      name = "Code Server";
      unit = "podman-code-server.service";
    }
    {
      name = "html2rss";
      unit = "podman-html2rss-web.service";
    }
    {
      name = "Plausible";
      unit = "plausible.service";
    }
    {
      name = "Redlib";
      unit = "podman-redlib.service";
    }
    {
      name = "Stalwart Mail";
      unit = "stalwart.service";
    }
    {
      name = "ESPHome";
      unit = "esphome.service";
    }
    {
      name = "go2rtc";
      unit = "podman-go2rtc.service";
    }
    {
      name = "OpenThread Border Router";
      unit = "podman-otbr.service";
    }
    {
      name = "Zigbee2MQTT";
      unit = "zigbee2mqtt.service";
    }
    {
      name = "Homepage";
      unit = "homepage-dashboard.service";
    }
    {
      name = "Grafana";
      unit = "grafana.service";
    }
    {
      name = "Magic API";
      unit = "website-api.service";
    }
    {
      name = "Max Miedinger";
      unit = "website-maxmiedinger.service";
    }
    {
      name = "Reciper";
      unit = "website-reciper.service";
    }
    {
      name = "Magic Homepage";
      unit = "website-startpage.service";
    }
    {
      name = "Transi";
      unit = "website-transi-eu.service";
    }
  ];
  hostedUnitRegex =
    lib.concatMapStringsSep "|" (entry: lib.replaceStrings [ "." ] [ "\\\\." ] entry.unit) hostedServices;
  statPanel =
    {
      id,
      title,
      x,
      expr,
      unit ? "short",
      max ? null,
      warning,
      critical,
    }:
    {
      inherit id title;
      type = "stat";
      gridPos = {
        h = 5;
        w = 6;
        inherit x;
        y = 0;
      };
      datasource = {
        type = "prometheus";
        uid = "prometheus";
      };
      fieldConfig.defaults = {
        inherit unit;
        min = 0;
        thresholds = {
          mode = "absolute";
          steps = [
            {
              color = "green";
              value = null;
            }
            {
              color = "orange";
              value = warning;
            }
            {
              color = "red";
              value = critical;
            }
          ];
        };
      }
      // lib.optionalAttrs (max != null) { inherit max; };
      options = {
        colorMode = "value";
        graphMode = "area";
        justifyMode = "auto";
        orientation = "auto";
        reduceOptions = {
          calcs = [ "lastNotNull" ];
          fields = "";
          values = false;
        };
        textMode = "auto";
      };
      targets = [
        {
          inherit expr;
          refId = "A";
        }
      ];
    };
  serviceValuePanel =
    {
      id,
      title,
      x,
      expr,
      unit ? "short",
    }:
    {
      inherit id title;
      type = "stat";
      gridPos = {
        h = 5;
        w = 6;
        inherit x;
        y = 5;
      };
      datasource = {
        type = "prometheus";
        uid = "prometheus";
      };
      fieldConfig.defaults = { inherit unit; };
      options = {
        colorMode = "none";
        graphMode = "none";
        justifyMode = "auto";
        orientation = "auto";
        reduceOptions = {
          calcs = [ "lastNotNull" ];
          fields = "";
          values = false;
        };
        textMode = "auto";
      };
      targets = [
        {
          inherit expr;
          refId = "A";
        }
      ];
    };
  dashboard = {
    uid = "magic-pylon-overview";
    title = "magic-pylon overview";
    tags = [ "homelab" ];
    editable = false;
    refresh = "15s";
    schemaVersion = 41;
    time = {
      from = "now-6h";
      to = "now";
    };
    templating.list = [
      {
        name = "service";
        label = "Hosted service";
        type = "custom";
        query = lib.concatMapStringsSep "," (entry: "${entry.name} : ${entry.unit}") hostedServices;
        current = {
          selected = true;
          text = "Home Assistant";
          value = "podman-homeassistant.service";
        };
        options = map (entry: {
          selected = entry.unit == "podman-homeassistant.service";
          text = entry.name;
          value = entry.unit;
        }) hostedServices;
      }
    ];
    panels = [
      (statPanel {
        id = 1;
        title = "CPU usage";
        x = 0;
        expr = ''100 - avg(rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])) * 100'';
        unit = "percent";
        max = 100;
        warning = 75;
        critical = 90;
      })
      (statPanel {
        id = 2;
        title = "Memory usage";
        x = 6;
        expr = ''(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100'';
        unit = "percent";
        max = 100;
        warning = 75;
        critical = 90;
      })
      (statPanel {
        id = 3;
        title = "Disk usage";
        x = 12;
        expr = ''(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100'';
        unit = "percent";
        max = 100;
        warning = 80;
        critical = 90;
      })
      (statPanel {
        id = 4;
        title = "Failed services";
        x = 18;
        expr = ''sum(systemd_unit_state{state="failed"})'';
        warning = 1;
        critical = 2;
      })
      {
        id = 5;
        title = "Service health";
        type = "stat";
        gridPos = {
          h = 5;
          w = 6;
          x = 0;
          y = 5;
        };
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        fieldConfig.defaults = {
          mappings = [
            {
              type = "value";
              options = {
                "0" = {
                  color = "red";
                  index = 0;
                  text = "Not active";
                };
                "1" = {
                  color = "green";
                  index = 1;
                  text = "Active";
                };
              };
            }
          ];
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "red";
                value = null;
              }
              {
                color = "green";
                value = 1;
              }
            ];
          };
        };
        options = {
          colorMode = "value";
          graphMode = "none";
          justifyMode = "auto";
          orientation = "auto";
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
          textMode = "auto";
        };
        targets = [
          {
            expr = ''systemd_unit_state{name="$service",state="active"}'';
            refId = "A";
          }
        ];
      }
      (serviceValuePanel {
        id = 6;
        title = "Service uptime";
        x = 6;
        expr = ''time() - systemd_unit_start_time_seconds{name="$service"}'';
        unit = "s";
      })
      (serviceValuePanel {
        id = 7;
        title = "Restart count";
        x = 12;
        expr = ''systemd_service_restart_total{name="$service"}'';
      })
      (serviceValuePanel {
        id = 8;
        title = "Current tasks";
        x = 18;
        expr = ''systemd_unit_tasks_current{name="$service"}'';
      })
      {
        id = 9;
        title = "Hosted service states";
        type = "table";
        gridPos = {
          h = 10;
          w = 24;
          x = 0;
          y = 28;
        };
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };
        options = {
          cellHeight = "sm";
          showHeader = true;
          sortBy = [
            {
              desc = false;
              displayName = "Service";
            }
          ];
        };
        targets = [
          {
            expr = ''systemd_unit_state{name=~"${hostedUnitRegex}",type="service"} == 1'';
            format = "table";
            instant = true;
            refId = "A";
          }
        ];
        transformations = [
          {
            id = "organize";
            options = {
              excludeByName = {
                __name__ = true;
                Time = true;
                Value = true;
                instance = true;
                job = true;
                type = true;
              };
              indexByName = {
                name = 0;
                state = 1;
              };
              renameByName = {
                name = "Service";
                state = "State";
              };
            };
          }
        ];
      }
      {
        id = 10;
        title = "Logs: \${service:text}";
        type = "logs";
        gridPos = {
          h = 18;
          w = 24;
          x = 0;
          y = 10;
        };
        datasource = {
          type = "loki";
          uid = "loki";
        };
        options = {
          dedupStrategy = "none";
          enableLogDetails = true;
          showLabels = false;
          showTime = true;
          sortOrder = "Descending";
          wrapLogMessage = true;
        };
        targets = [
          {
            expr = ''{host="magic-pylon",unit="$service"}'';
            queryType = "range";
            refId = "A";
          }
        ];
      }
    ];
  };
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable the local Grafana monitoring stack";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "logs.${homelab.baseDomain}";
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "Grafana";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "System metrics and service logs";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "grafana.svg";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
    };
  };

  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings = {
        server = {
          domain = cfg.url;
          enforce_domain = true;
          enable_gzip = true;
          root_url = "https://${cfg.url}/";
        };
        security = {
          admin_user = homelab.user;
          admin_password = "$__file{${grafanaDataDir}/admin-password}";
          secret_key = "$__file{${grafanaDataDir}/secret-key}";
          disable_gravatar = true;
          cookie_secure = true;
          cookie_samesite = "strict";
        };
        "auth.anonymous" = {
          enabled = true;
          org_role = "Viewer";
          hide_version = true;
        };
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
          check_for_plugin_updates = false;
        };
        dashboards.default_home_dashboard_path = "/etc/grafana-dashboards/magic-pylon-overview.json";
        news.news_feed_enabled = false;
        plugins = {
          plugin_admin_enabled = false;
          preinstall_disabled = true;
          public_key_retrieval_disabled = true;
        };
        snapshots.external_enabled = false;
      };
      provision = {
        enable = true;
        datasources.settings = {
          apiVersion = 1;
          prune = true;
          datasources = [
            {
              name = "Prometheus";
              uid = "prometheus";
              type = "prometheus";
              access = "proxy";
              url = "http://127.0.0.1:${toString config.services.prometheus.port}";
              isDefault = true;
              editable = false;
              jsonData.timeInterval = "15s";
            }
            {
              name = "Loki";
              uid = "loki";
              type = "loki";
              access = "proxy";
              url = "http://127.0.0.1:3100";
              editable = false;
            }
          ];
        };
        dashboards.settings = {
          apiVersion = 1;
          providers = [
            {
              name = "Homelab";
              disableDeletion = true;
              options.path = "/etc/grafana-dashboards";
            }
          ];
        };
      };
    };

    environment.etc."grafana-dashboards/magic-pylon-overview.json".text = builtins.toJSON dashboard;

    systemd.services.grafana.preStart = lib.mkBefore ''
      umask 077
      for secret in admin-password secret-key; do
        path="${grafanaDataDir}/$secret"
        if [[ ! -s "$path" ]]; then
          ${lib.getExe pkgs.openssl} rand -hex -out "$path" 32
        fi
      done
    '';

    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      retentionTime = "90d";
      globalConfig.scrape_interval = "15s";
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [ { targets = [ "127.0.0.1:9100" ]; } ];
        }
        {
          job_name = "systemd";
          static_configs = [ { targets = [ "127.0.0.1:9558" ]; } ];
        }
        {
          job_name = "prometheus";
          static_configs = [ { targets = [ "127.0.0.1:${toString config.services.prometheus.port}" ]; } ];
        }
        {
          job_name = "loki";
          static_configs = [ { targets = [ "127.0.0.1:3100" ]; } ];
        }
        {
          job_name = "alloy";
          static_configs = [ { targets = [ "127.0.0.1:12345" ]; } ];
        }
      ];
      exporters = {
        node = {
          enable = true;
          listenAddress = "127.0.0.1";
        };
        systemd = {
          enable = true;
          listenAddress = "127.0.0.1";
          extraFlags = [ "--systemd.collector.enable-restart-count" ];
        };
      };
    };

    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server = {
          http_listen_address = "127.0.0.1";
          http_listen_port = 3100;
          grpc_listen_address = "127.0.0.1";
        };
        common = {
          instance_addr = "127.0.0.1";
          path_prefix = lokiDataDir;
          storage.filesystem = {
            chunks_directory = "${lokiDataDir}/chunks";
            rules_directory = "${lokiDataDir}/rules";
          };
          replication_factor = 1;
          ring.kvstore.store = "inmemory";
        };
        query_range.results_cache.cache.embedded_cache = {
          enabled = true;
          max_size_mb = 64;
        };
        schema_config.configs = [
          {
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];
        limits_config = {
          retention_period = "720h";
          volume_enabled = true;
          discover_log_levels = true;
        };
        compactor = {
          working_directory = "${lokiDataDir}/compactor";
          retention_enabled = true;
          delete_request_store = "filesystem";
        };
        analytics.reporting_enabled = false;
      };
    };

    services.alloy = {
      enable = true;
      extraFlags = [ "--disable-reporting" ];
    };
    environment.etc."alloy/config.alloy".text = ''
      loki.relabel "journal" {
        forward_to = []

        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "service_name"
        }
        rule {
          source_labels = ["__journal_container_name"]
          target_label  = "container"
        }
        rule {
          source_labels = ["__journal_priority_keyword"]
          target_label  = "level"
        }
        rule {
          source_labels = ["__journal_syslog_identifier"]
          target_label  = "syslog_identifier"
        }
      }

      loki.source.journal "system" {
        forward_to    = [loki.write.local.receiver]
        relabel_rules = loki.relabel.journal.rules
        max_age       = "24h"
        labels        = { host = "magic-pylon" }
      }

      loki.write "local" {
        endpoint {
          url = "http://127.0.0.1:3100/loki/api/v1/push"
        }
      }
    '';

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        @notTailscale not remote_ip 100.64.0.0/10 fd7a:115c:a1e0::/48
        respond @notTailscale 403
        reverse_proxy http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}
      '';
    };

    environment.persistence."/".directories = [
      {
        directory = grafanaDataDir;
        user = "grafana";
        group = "grafana";
        mode = "0700";
      }
      {
        directory = lokiDataDir;
        user = "loki";
        group = "loki";
        mode = "0750";
      }
      {
        directory = "/var/lib/prometheus2";
        user = "prometheus";
        group = "prometheus";
        mode = "0700";
      }
      "/var/lib/private/alloy"
    ];
  };
}
