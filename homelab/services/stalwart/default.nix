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

  # The service was first enabled before NixOS 26.05, so keep the legacy
  # user/group and state layout while using the renamed 26.05 module/unit.
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

    adminPasswordFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing the plaintext fallback admin password.
        The service hashes it (sha-512 crypt) at start time and feeds the
        hash to Stalwart's authentication.fallback-admin.secret.
      '';
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
    services.stalwart = {
      enable = true;
      stateVersion = "25.11";
      package = pkgs.stalwart-mail;
      openFirewall = false;
      user = svcUser;
      group = svcGroup;

      # systemd LoadCredential reads the agenix-decrypted file as root and exposes it
      # as a per-unit credential at /run/credentials/stalwart.service/resendApiKey.
      credentials = {
        resendApiKey  = toString cfg.resendApiKeyFile;
        adminPassword = toString cfg.adminPasswordFile;
      };

      settings = {
        # Tell Stalwart that these prefixes belong in the local TOML, not the
        # runtime database. Without this, every restart logs ~20 "Database key
        # defined in local configuration" warnings for our declarative config.
        # Defining ANY config.local-keys.* replaces the upstream defaults, so
        # we re-include them all alongside ours.
        config.local-keys = {
          # upstream defaults
          server                = "server.*";
          certificate           = "certificate.*";
          local-keys            = "config.local-keys.*";
          fallback-admin        = "authentication.fallback-admin.*";
          cluster               = "cluster.*";
          storage-data          = "storage.data";
          storage-blob          = "storage.blob";
          storage-lookup        = "storage.lookup";
          storage-fts           = "storage.fts";
          storage-directory     = "storage.directory";
          # our additions for this declarative deployment
          store                 = "store.*";
          storage-extra         = "storage.*";
          directory             = "directory.*";
          session               = "session.*";
          queue                 = "queue.*";
          tracer                = "tracer.*";
          webadmin              = "webadmin.*";
          resolver              = "resolver.*";
          spam-filter-resource  = "spam-filter.resource";
          authentication        = "authentication.*";
        };

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
        };

        directory."internal" = {
          type = "internal";
          store = "pg";
          # Enable catch-all + sub-addressing (foo+bar@) at the directory level.
          # Per-domain catch-all is then configured by adding an "@<domain>"
          # alias to whichever account should receive unmatched mail.
          options.catch-all = true;
          options.subaddressing = true;
        };

        # v0.13+ outbound routing: queue.strategy.route picks a routing strategy
        # by name; the actual relay/MX/local strategy lives under queue.route.<id>.
        queue.strategy.route = [
          { "if" = "rcpt_domain == '${cfg.primaryDomain}'"; "then" = "'local'"; }
          { "else" = "'resend'"; }
        ];
        queue.route."resend" = {
          type = "relay";
          address = "smtp.resend.com";
          port = 465;
          protocol = "smtp";
          tls.implicit = true;
          auth = {
            username = "resend";
            # Secret loaded via systemd LoadCredential (credentials option above).
            secret = "%{file:/run/credentials/stalwart.service/resendApiKey}%";
          };
        };

        session.auth = {
          # Stalwart parses session.auth.mechanisms as an IfBlock whose value is
          # an expression-string set, NOT a TOML array. Pass the literal expression.
          mechanisms = "[plain, login]";
          directory = "'internal'";
          require = [
            { "if" = "listener == 'submission' || listener == 'submissions'"; "then" = true; }
            { "else" = false; }
          ];
        };

        # Relax Stalwart's strict-by-default EHLO validation on port 25. Many
        # legitimate senders use non-FQDN EHLOs or have PTR/EHLO mismatches that
        # the default `reject-non-fqdn = true` would reject with 550 5.5.0.
        session.ehlo = {
          require = true;
          reject-non-fqdn = false;
        };

        # All inbound v4 mail comes through the VPS WireGuard tunnel and is
        # source-IP-masqueraded to 172.16.16.1 on this side; without this
        # allowlist, Stalwart's auto-ban quickly flags 172.16.16.1 after any
        # noisy peer (bad EHLO, spam pattern) and then rejects every legitimate
        # v4 sender with a TCP RST. Allowlisted IPs bypass rate limits and
        # auto-banning entirely. Stalwart's quirky format puts the IP itself
        # in the *key* with an empty value (set_values reads the sub-key as
        # the IP).
        server.allowed-ip."172.16.16.1" = "";

        # Bootstrap admin: only honored if no equivalent account exists in the directory.
        # Rotate after first login via the admin UI (My Account → Change Password).
        # The plaintext password lives in agenix; ExecStartPre hashes it into
        # /run/stalwart-mail/admin-secret on every start (random salt, but
        # crypt-compatible — different bytes each run, same password validates).
        authentication.fallback-admin = {
          user = "admin";
          secret = "%{file:/run/stalwart-mail/admin-secret}%";
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
      "stalwart.service"
    ];
    # Add stalwart-mail to the homelab user's group so it can write into the
    # persistence dir owned by ${homelab.user}; this keeps mail files
    # accessible via SMB and to borg-ui backups running as ${homelab.user}.
    users.users.${svcUser}.extraGroups = [
      config.services.caddy.group
      homelab.group
    ];

    # Data dir owned by the homelab user (so SMB and borg-ui can read all
    # mail files). Setgid (2770) ensures every file/dir stalwart-mail creates
    # inherits ${homelab.group} as its group, which combined with the relaxed
    # UMask=0007 in the service config gives ${homelab.user} full rw access
    # to all mail data via group membership.
    environment.persistence."/".directories = [
      { directory = cfg.dataDir; user = homelab.user; group = homelab.group; mode = "2770"; }
    ];

    systemd.services.stalwart = {
      after    = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      serviceConfig = {
        # Upstream module restricts to AF_INET/AF_INET6; postgres lives on a
        # Unix-domain socket at /run/postgresql, so AF_UNIX must be added.
        RestrictAddressFamilies = lib.mkForce [ "AF_INET" "AF_INET6" "AF_UNIX" ];

        # Upstream ReadWritePaths is /var/lib/stalwart-mail only; our blob
        # store at /persist/opt/services/stalwart needs to be writable too,
        # otherwise every inbound message fails the blob spool with "Read-only
        # file system" (os error 30).
        ReadWritePaths = [ cfg.dataDir ];

        # Upstream UMask=0077 makes new files 0600 — unreadable for
        # ${homelab.user} via group. Loosen to 0007 so files are 0660 / dirs
        # 0770: full rw for owner (stalwart-mail) AND group (${homelab.group}).
        UMask = lib.mkForce "0007";

        # Writable tmpfs at /run/stalwart-mail/, used for the hashed admin secret.
        RuntimeDirectory = "stalwart-mail";
        RuntimeDirectoryMode = "0750";

        # Pre-start: read plaintext admin password from systemd credential store,
        # produce a sha-512 crypt hash (no trailing newline), and drop it where
        # Stalwart's %{file:…}% expansion can read it.
        ExecStartPre = [
          (pkgs.writeShellScript "stalwart-hash-admin" ''
            set -eu
            ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 -s \
              < "$CREDENTIALS_DIRECTORY/adminPassword" \
              | ${pkgs.coreutils}/bin/tr -d '\n' \
              > /run/stalwart-mail/admin-secret
          '')
        ];
      };
    };
  };
}
