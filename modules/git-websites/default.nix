{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.git-websites;

  siteType = types.submodule (
    { name, config, ... }:
    {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable this Git-deployed website.";
        };

        host = mkOption {
          type = types.str;
          default = name;
          description = "Public hostname served by Caddy.";
        };

        aliases = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Additional hostnames served by the same Caddy virtual host.";
        };

        repo = mkOption {
          type = types.str;
          description = "Git repository URL to clone and pull.";
        };

        dataDir = mkOption {
          type = types.path;
          default = "/var/lib/git-websites/${name}";
          description = "Persistent directory containing the checked out repository.";
        };

        kind = mkOption {
          type = types.enum [
            "static"
            "backend"
          ];
          default = "static";
          description = "Whether Caddy should serve built files or reverse proxy a backend process.";
        };

        port = mkOption {
          type = types.nullOr types.port;
          default = null;
          description = "Localhost port for backend websites.";
        };

        user = mkOption {
          type = types.str;
          default = "git-website";
          description = "User account under which update/build/start commands run.";
        };

        group = mkOption {
          type = types.str;
          default = "git-website";
          description = "Group under which update/build/start commands run.";
        };

        home = mkOption {
          type = types.path;
          default = config.dataDir;
          description = "HOME used for Git SSH configuration and known_hosts.";
        };

        installCommand = mkOption {
          type = types.str;
          default = "bun install";
          description = "Command run after clone or pull before building.";
        };

        buildCommand = mkOption {
          type = types.str;
          default = "";
          description = "Optional build command.";
        };

        startCommand = mkOption {
          type = types.str;
          default = "";
          description = "Backend start command, executed from the repository root.";
        };

        caddyExtraConfig = mkOption {
          type = types.lines;
          default = "";
          description = "Additional Caddy directives inserted before the default static file server or backend reverse proxy.";
        };

        webRoot = mkOption {
          type = types.str;
          default = "dist";
          description = "Directory inside the repository that Caddy serves for static websites.";
        };

        spaFallback = mkOption {
          type = types.bool;
          default = false;
          description = "Serve index.html for unmatched static paths.";
        };

        acmeHost = mkOption {
          type = types.str;
          default = config.host;
          description = "ACME certificate name to use for this virtual host.";
        };

        manageAcme = mkOption {
          type = types.bool;
          default = true;
          description = "Whether this module should declare the ACME certificate.";
        };

        acmeDnsProvider = mkOption {
          type = types.str;
          default = "cloudflare";
          description = "DNS provider for ACME DNS-01 issuance.";
        };

        acmeCredentialsFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Environment file containing ACME DNS provider credentials.";
        };

        homepage = {
          name = mkOption {
            type = types.str;
            default = config.host;
            description = "Display name in Homepage.";
          };

          description = mkOption {
            type = types.str;
            default = "Git-deployed website";
            description = "Description in Homepage.";
          };

          icon = mkOption {
            type = types.str;
            default = "mdi-web";
            description = "Icon in Homepage.";
          };

          category = mkOption {
            type = types.str;
            default = "Sites";
            description = "Homepage category.";
          };

          siteMonitor = mkOption {
            type = types.bool;
            default = true;
            description = "Whether Homepage should monitor this site's public URL.";
          };

          siteMonitorUrl = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Optional Homepage monitor URL. Defaults to the website root.";
          };

          widget = mkOption {
            type = types.nullOr (types.attrsOf types.anything);
            default = null;
            description = "Optional Homepage service widget.";
          };

          widgets = mkOption {
            type = types.nullOr (types.listOf (types.attrsOf types.anything));
            default = null;
            description = "Optional Homepage service widgets.";
          };
        };
      };
    }
  );

  enabledSites = filterAttrs (_: site: cfg.enable && site.enable) cfg.sites;
  backendSites = filterAttrs (_: site: site.kind == "backend") enabledSites;
  managedAcmeHosts = unique (
    map (site: site.acmeHost) (filter (site: site.manageAcme) (attrValues enabledSites))
  );

  serviceName = name: "website-${replaceStrings [ "." ] [ "-" ] name}";

  updateScript =
    name: site:
    pkgs.writeShellApplication {
      name = "${serviceName name}-update";
      runtimeInputs = [
        pkgs.bun
        pkgs.git
        pkgs.nodejs
        pkgs.openssh
      ];
      text = ''
        set -euo pipefail

        export HOME="${site.home}"
        export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new"

        mkdir -p "${site.dataDir}"

        if [ -d "${site.dataDir}/repo/.git" ] && [ ! -d "${site.dataDir}/.git" ]; then
          shopt -s dotglob nullglob
          for path in "${site.dataDir}/repo"/*; do
            mv "$path" "${site.dataDir}/"
          done
          rmdir "${site.dataDir}/repo"
        fi

        if [ ! -d "${site.dataDir}/.git" ]; then
          shopt -s dotglob nullglob
          existing=("${site.dataDir}"/*)
          if (( ''${#existing[@]} > 0 )); then
            echo "${site.dataDir} is not empty and is not a Git checkout" >&2
            exit 1
          fi
          git clone "${site.repo}" "${site.dataDir}"
        else
          git -C "${site.dataDir}" pull --ff-only
        fi

        cd "${site.dataDir}"

        ${optionalString (site.installCommand != "") site.installCommand}
        ${optionalString (site.buildCommand != "") site.buildCommand}
      '';
    };

  startScript =
    name: site:
    pkgs.writeShellApplication {
      name = "${serviceName name}-start";
      runtimeInputs = [
        pkgs.bun
        pkgs.nodejs
      ];
      text = ''
        set -euo pipefail

        cd "${site.dataDir}"
        ${site.startCommand}
      '';
    };

  mkSiteService =
    name: site:
    let
      updater = updateScript name site;
      starter = startScript name site;
    in
    if site.kind == "static" then
      {
        description = "Update static website ${site.host}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          pkgs.bun
          pkgs.git
          pkgs.nodejs
          pkgs.openssh
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = site.user;
          Group = site.group;
          WorkingDirectory = site.dataDir;
          ExecStart = getExe updater;
        };
        wantedBy = [ "multi-user.target" ];
      }
    else
      {
        description = "Website backend ${site.host}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          pkgs.bun
          pkgs.git
          pkgs.nodejs
          pkgs.openssh
        ];
        environment = {
          HOST = "127.0.0.1";
          HOSTNAME = "127.0.0.1";
          PORT = toString site.port;
          NODE_ENV = "production";
        };
        serviceConfig = {
          User = site.user;
          Group = site.group;
          WorkingDirectory = site.dataDir;
          ExecStartPre = getExe updater;
          ExecStart = getExe starter;
          Restart = "on-failure";
          RestartSec = "5s";
        };
        wantedBy = [ "multi-user.target" ];
      };

  mkVirtualHost = site: {
    useACMEHost = site.acmeHost;
    serverAliases = site.aliases;
    extraConfig =
      if site.kind == "static" then
        ''
          ${site.caddyExtraConfig}
          root * ${site.dataDir}/${site.webRoot}
          ${optionalString site.spaFallback "try_files {path} /index.html"}
          file_server
        ''
      else
        ''
          ${site.caddyExtraConfig}
          reverse_proxy http://127.0.0.1:${toString site.port}
        '';
  };
in
{
  options.services.git-websites = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Git-deployed website services.";
    };

    sites = mkOption {
      type = types.attrsOf siteType;
      default = { };
      description = "Git-deployed website instances keyed by service name.";
    };
  };

  config = mkIf cfg.enable {
    assertions =
      mapAttrsToList (name: site: {
        assertion = site.kind == "static" || site.port != null;
        message = "Website backend ${name} must define a port.";
      }) backendSites
      ++ mapAttrsToList (name: site: {
        assertion = site.kind == "static" || site.startCommand != "";
        message = "Website backend ${name} must define startCommand.";
      }) backendSites
      ++ mapAttrsToList (name: site: {
        assertion = !site.manageAcme || site.acmeCredentialsFile != null;
        message = "Website ${name} manages ACME but has no acmeCredentialsFile.";
      }) enabledSites;

    users.users.git-website = mkIf (any (site: site.user == "git-website") (attrValues enabledSites)) {
      group = "git-website";
      home = "/var/lib/git-websites";
      createHome = true;
      description = "Git website service user";
      isSystemUser = true;
    };

    users.groups.git-website = mkIf (any (site: site.group == "git-website") (attrValues enabledSites)) { };

    security.acme.certs = genAttrs managedAcmeHosts (
      acmeHost:
      let
        site = findFirst (candidate: candidate.acmeHost == acmeHost && candidate.manageAcme) null (
          attrValues enabledSites
        );
      in
      {
        reloadServices = [ "caddy.service" ];
        dnsProvider = site.acmeDnsProvider;
        dnsResolver = "1.1.1.1:53";
        dnsPropagationCheck = true;
        group = config.services.caddy.group;
        environmentFile = site.acmeCredentialsFile;
      }
    );

    services.caddy.virtualHosts = mapAttrs' (
      _: site: nameValuePair site.host (mkVirtualHost site)
    ) enabledSites;

    systemd.services = mapAttrs' (
      name: site: nameValuePair (serviceName name) (mkSiteService name site)
    ) enabledSites;

    systemd.tmpfiles.rules = mapAttrsToList (
      _: site: "d ${site.dataDir} 0755 ${site.user} ${site.group} - -"
    ) enabledSites;
  };
}
