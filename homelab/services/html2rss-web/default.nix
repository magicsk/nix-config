{ config, lib, pkgs, ... }:
let
  service = "html2rss-web";
  browserlessService = "${service}-browserless";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;
  networkSubnet = "172.30.15.0/24";
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption {
      description = "Enable html2rss-web";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/${service}";
    };
    configDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/${service}/config";
    };
    url = lib.mkOption {
      type = lib.types.str;
      default = "html2rss.${homelab.baseDomain}";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
    };
    browserlessPort = lib.mkOption {
      type = lib.types.port;
      default = 4002;
    };
    homepage.name = lib.mkOption {
      type = lib.types.str;
      default = "html2rss";
    };
    homepage.description = lib.mkOption {
      type = lib.types.str;
      default = "Turn websites into RSS feeds";
    };
    homepage.icon = lib.mkOption {
      type = lib.types.str;
      default = "mdi-rss";
    };
    homepage.category = lib.mkOption {
      type = lib.types.str;
      default = "Services";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation = {
      podman.enable = true;
      oci-containers.containers = {
        ${browserlessService} = {
          image = "ghcr.io/browserless/chromium";
          autoStart = true;
          environment = {
            PORT = toString cfg.browserlessPort;
            CONCURRENT = "2";
          };
          environmentFiles = [
            "${cfg.dataDir}/browserless.env"
          ];
          extraOptions = [
            "--network=${service}"
            "--shm-size=2g"
          ];
        };

        ${service} = {
          image = "docker.io/html2rss/web:1";
          autoStart = true;
          volumes = [
            "${cfg.configDir}/feeds.yml:/app/config/feeds.yml:ro"
          ];
          ports = [
            "127.0.0.1:${toString cfg.port}:4000"
          ];
          environment = {
            RACK_ENV = "production";
            PORT = "4000";
            BUILD_TAG = "nixos";
            GIT_SHA = "nixos";
            SENTRY_DSN = "";
            SENTRY_ENABLE_LOGS = "false";
            AUTO_SOURCE_ENABLED = "true";
            RACK_TIMEOUT_SERVICE_TIMEOUT = "45";
            RACK_TIMEOUT_WAIT_TIMEOUT = "60";
            BROWSERLESS_IO_WEBSOCKET_URL = "ws://${browserlessService}:${toString cfg.browserlessPort}";
          };
          environmentFiles = [
            "${cfg.dataDir}/html2rss.env"
          ];
          extraOptions = [ "--network=${service}" ];
          dependsOn = [ browserlessService ];
        };
      };
    };

    systemd.services."${service}-secrets" = {
      description = "Create ${service} environment secrets";
      before = [
        "podman-${service}.service"
        "podman-${browserlessService}.service"
      ];
      requiredBy = [
        "podman-${service}.service"
        "podman-${browserlessService}.service"
      ];
      path = [
        pkgs.coreutils
        pkgs.openssl
      ];
      script = ''
        set -eu
        umask 077

        data_dir=${lib.escapeShellArg cfg.dataDir}
        config_dir=${lib.escapeShellArg cfg.configDir}
        homelab_user=${lib.escapeShellArg homelab.user}
        homelab_group=${lib.escapeShellArg homelab.group}
        html_env="$data_dir/html2rss.env"
        browserless_env="$data_dir/browserless.env"
        feeds_config="$config_dir/feeds.yml"

        install -d -o "$homelab_user" -g "$homelab_group" -m 0750 "$data_dir" "$config_dir"

        if [ ! -e "$feeds_config" ]; then
          tmp_feeds="$(mktemp "$config_dir/.feeds.yml.XXXXXX")"
          cat > "$tmp_feeds" <<'EOF'
auth:
  accounts:
    - username: "admin"
      token: "<%= Html2rss::Web::RuntimeEnv.admin_access_token %>"
      allowed_urls:
        - "*"
    - username: "health-check"
      token: "<%= Html2rss::Web::RuntimeEnv.health_check_token %>"
      allowed_urls: [ ]

stylesheets:
  - href: "/rss.xsl"
    media: "all"
    type: "text/xsl"

headers:
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36"

feeds: { }
EOF
          install -o "$homelab_user" -g "$homelab_group" -m 0644 "$tmp_feeds" "$feeds_config"
          rm -f "$tmp_feeds"
        fi
        chown "$homelab_user:$homelab_group" "$feeds_config"
        chmod 0644 "$feeds_config"

        if [ -f "$html_env" ]; then
          set -a
          . "$html_env"
          set +a
        fi

        if [ -z "''${HTML2RSS_SECRET_KEY:-}" ]; then
          HTML2RSS_SECRET_KEY="$(openssl rand -hex 32)"
        fi
        if [ -z "''${HEALTH_CHECK_TOKEN:-}" ]; then
          HEALTH_CHECK_TOKEN="$(openssl rand -hex 24)"
        fi
        if [ -z "''${HTML2RSS_ACCESS_TOKEN:-}" ]; then
          HTML2RSS_ACCESS_TOKEN="$(openssl rand -hex 24)"
        fi
        if [ -z "''${BROWSERLESS_IO_API_TOKEN:-}" ]; then
          BROWSERLESS_IO_API_TOKEN="$(openssl rand -hex 24)"
        fi

        tmp_html="$(mktemp "$data_dir/.html2rss.env.XXXXXX")"
        cat > "$tmp_html" <<EOF
HTML2RSS_SECRET_KEY=$HTML2RSS_SECRET_KEY
HEALTH_CHECK_TOKEN=$HEALTH_CHECK_TOKEN
HTML2RSS_ACCESS_TOKEN=$HTML2RSS_ACCESS_TOKEN
BROWSERLESS_IO_API_TOKEN=$BROWSERLESS_IO_API_TOKEN
EOF
        install -o root -g "$homelab_group" -m 0640 "$tmp_html" "$html_env"
        rm -f "$tmp_html"

        tmp_browserless="$(mktemp "$data_dir/.browserless.env.XXXXXX")"
        cat > "$tmp_browserless" <<EOF
TOKEN=$BROWSERLESS_IO_API_TOKEN
EOF
        install -o root -g "$homelab_group" -m 0640 "$tmp_browserless" "$browserless_env"
        rm -f "$tmp_browserless"
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    systemd.services."podman-network-${service}" = {
      description = "Create Podman network for ${service}";
      before = [
        "podman-${service}.service"
        "podman-${browserlessService}.service"
      ];
      after = [ "podman.service" ];
      requiredBy = [
        "podman-${service}.service"
        "podman-${browserlessService}.service"
      ];
      path = [ pkgs.podman ];
      script = ''
        podman network inspect ${service} > /dev/null 2>&1 || \
          podman network create --subnet ${networkSubnet} ${service}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # html2rss-web and Browserless fetch arbitrary public sites; route those
    # checks over the home connection instead of the WireGuard VPS path.
    networking.wg-quick.interfaces.wg0.postUp = ''
      ${pkgs.iproute2}/bin/ip rule add from ${networkSubnet} table main priority 86
    '';
    networking.wg-quick.interfaces.wg0.preDown = ''
      ${pkgs.iproute2}/bin/ip rule del from ${networkSubnet} table main priority 86 || true
    '';

    services.caddy.virtualHosts."${cfg.url}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:${toString cfg.port}
      '';
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${homelab.user} ${homelab.group} - -"
      "d ${cfg.configDir} 0750 ${homelab.user} ${homelab.group} - -"
      "z ${cfg.configDir}/feeds.yml 0644 ${homelab.user} ${homelab.group} - -"
    ];

    environment.persistence."/".directories = [
      {
        directory = cfg.dataDir;
        user = homelab.user;
        group = homelab.group;
        mode = "0750";
      }
    ];
  };
}
