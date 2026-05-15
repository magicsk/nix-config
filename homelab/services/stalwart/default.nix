{ config, lib, pkgs, ... }:
let
  service = "stalwart";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;

  adminHost  = "${service}.${homelab.baseDomain}";

  # Match OS user so peer-auth on /run/postgresql works; ensureDBOwnership
  # additionally requires the pg user and database to share a name.
  dbName = svcUser;
  dbUser = svcUser;

  # nixpkgs 25.11 still ships the module as services.stalwart-mail with user/group stalwart-mail.
  svcUser  = "stalwart-mail";
  svcGroup = "stalwart-mail";
in
{
  options.homelab.services.${service} = {
    enable = lib.mkEnableOption "Stalwart mail server";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.config}/${service}";
    };

    url = lib.mkOption {
      type = lib.types.str;
      default = adminHost;
    };

    resendApiKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a file containing the Resend SMTP API key.";
    };

    primaryDomain = lib.mkOption {
      type = lib.types.str;
      default = homelab.baseDomain;
    };

    homepage = {
      name        = lib.mkOption { type = lib.types.str; default = "Stalwart Mail"; };
      description = lib.mkOption { type = lib.types.str; default = "Self-hosted mail server"; };
      icon        = lib.mkOption { type = lib.types.str; default = "stalwart.svg"; };
      category    = lib.mkOption { type = lib.types.str; default = "Services"; };
    };
  };

  config = lib.mkIf cfg.enable {
    services.stalwart-mail = {
      enable = true;
      package = pkgs.stalwart-mail;
      openFirewall = false;

      # systemd LoadCredential reads the agenix-decrypted file as root and exposes it
      # as a per-unit credential at /run/credentials/stalwart-mail.service/resendApiKey.
      credentials = {
        resendApiKey = toString cfg.resendApiKeyFile;
      };

      settings = {
        certificate.default = {
          cert        = "%{file:/var/lib/acme/${homelab.baseDomain}/fullchain.pem}%";
          private-key = "%{file:/var/lib/acme/${homelab.baseDomain}/key.pem}%";
          default     = true;
        };

        server.listener = {
          smtp        = { bind = [ "[::]:25"  ]; protocol = "smtp"; };
          submissions = { bind = [ "[::]:465" ]; protocol = "smtp"; tls.implicit = true; };
          submission  = { bind = [ "[::]:587" ]; protocol = "smtp"; };
          imap        = { bind = [ "[::]:143" ]; protocol = "imap"; };
          imaps       = { bind = [ "[::]:993" ]; protocol = "imap"; tls.implicit = true; };
          http        = { bind = [ "127.0.0.1:8080" ]; protocol = "http"; };
        };

        store."pg"      = { type = "postgresql"; host = "/run/postgresql"; database = dbName; user = dbUser; };
        store."blob-fs" = { type = "fs";         path = "${cfg.dataDir}/blobs"; };
        storage = {
          data = "pg"; blob = "blob-fs"; fts = "pg"; lookup = "pg"; directory = "internal";
          # v0.14+ requires storage.in-memory for security/anti-spam state; nixpkgs default omits it.
          in-memory = "pg";
        };

        directory."internal" = { type = "internal"; store = "pg"; };

        # v0.13+ outbound routing: use queue.strategy.route instead of the deprecated next-hop.
        queue.strategy.route = [
          { "if" = "rcpt_domain != '${cfg.primaryDomain}'"; "then" = "'resend'"; }
          { "else" = "'local'"; }
        ];
        remote."resend" = {
          address = "smtp.resend.com";
          port = 465;
          protocol = "smtp";
          tls.implicit = true;
          auth = {
            username = "resend";
            # Secret loaded via systemd LoadCredential (credentials option above).
            secret = "%{file:/run/credentials/stalwart-mail.service/resendApiKey}%";
          };
        };

        session.auth = {
          mechanisms = [ "PLAIN" "LOGIN" ];
          directory = "'internal'";
          require = [
            { "if" = "listener == 'submission' || listener == 'submissions'"; "then" = true; }
            { "else" = false; }
          ];
        };
      };
    };

    services.postgresql = {
      ensureDatabases = [ dbName ];
      ensureUsers = [{
        name = dbUser;
        ensureDBOwnership = true;
      }];
    };

    services.caddy.virtualHosts."${adminHost}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:8080
      '';
    };

    networking.firewall.allowedTCPPorts = [ 25 465 587 143 993 ];

    security.acme.certs."${homelab.baseDomain}".reloadServices = [
      "stalwart-mail.service"
    ];
    users.users.${svcUser}.extraGroups = [ config.services.caddy.group ];

    environment.persistence."/".directories = [
      { directory = cfg.dataDir; user = svcUser; group = svcGroup; mode = "0750"; }
    ];

    systemd.services.stalwart-mail = {
      after    = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      # Upstream module restricts to AF_INET/AF_INET6; we connect to postgres
      # over a Unix-domain socket at /run/postgresql, so AF_UNIX must be added.
      serviceConfig.RestrictAddressFamilies = lib.mkForce [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    };
  };
}
