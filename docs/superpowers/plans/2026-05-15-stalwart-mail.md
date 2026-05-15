# Stalwart Mail Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy self-hosted Stalwart mail server on `magic-pylon` for `@magicsk.eu` mail. PostgreSQL backend, Resend SMTP relay for outbound, Oracle VPS port-forwards inbound through WireGuard.

**Architecture:** New `homelab.services.stalwart` module (native NixOS `services.stalwart-mail`), shares wildcard ACME cert with Caddy, admin UI on Tailscale-only `stalwart.magicsk.eu` and SMTP/IMAP on public `mail.magicsk.eu`. Cross-cutting: relocate `postgresqlBackup` from the disabled `homelab.services.backup` module to the postgres module so PG dumps actually run.

**Tech Stack:** NixOS `nixos-25.11`, `services.stalwart-mail`, `services.postgresql`, `services.caddy`, `security.acme` (Cloudflare DNS), agenix, Resend SMTP relay, iptables on Oracle VPS, deploy via `just deploy magic-pylon`.

**Spec:** `docs/superpowers/specs/2026-05-15-stalwart-mail-design.md`

---

## Implementation notes (post-execution)

The Task 2 module landed in commits `44347ea` and `cf73d7e` with schema adaptations for the actual nixpkgs 25.11 / Stalwart 0.14.1 in use:

- `queue.outbound.next-hop` → `queue.strategy.route` (the old key triggers a hard nixpkgs assertion)
- `else = false` → `else = "'local'"` for the outbound route fallback (v0.13+ expects a strategy name)
- Secret passed via `services.stalwart-mail.credentials` (systemd LoadCredential) instead of direct `%{file:${cfg.resendApiKeyFile}}%` reads, because `ProtectSystem=strict` in the stalwart unit blocks reads from `/run/agenix/`.

See `homelab/services/stalwart/default.nix` for the authoritative module code.

## Preconditions

Before starting:

- [ ] `resendApiKey.age` exists in the nix-private repo (`github:magicsk/nix-private`). User has confirmed this is done.
- [ ] You have a Resend account with an API key generated.
- [ ] You have access to the OCI Console for the VPS at `132.226.217.72`.
- [ ] You have access to the Cloudflare dashboard for `magicsk.eu`.
- [ ] `magic-pylon` is reachable via `ssh magic-pylon` (or `ssh magic-pylon.local`).

---

## File Structure

**New files:**
- `homelab/services/stalwart/default.nix` — the service module (~150 lines)

**Modified files:**
- `homelab/services/postgresql/default.nix` — enable `services.postgresqlBackup` with location on Nitor
- `homelab/services/backup/default.nix` — remove the now-redundant `postgresqlBackup` block (still gated behind disabled module, but keeping a single source of truth)
- `homelab/services/default.nix` — add `./stalwart` to the imports list
- `machines/nixos/magic-pylon/homelab/default.nix` — enable `stalwart` with `resendApiKeyFile`
- `machines/nixos/magic-pylon/secrets/default.nix` — add `resendApiKey` agenix entry

**External (no repo change, manual one-time):**
- Cloudflare DNS: A, MX, SPF, DKIM, DMARC records
- Resend dashboard: add `magicsk.eu`, copy records to Cloudflare
- Oracle VPS: iptables port-forward rules, OCI Security List, PTR

---

### Task 0: Relocate `postgresqlBackup` to the postgres module

**Goal:** Make `postgresqlBackup` actually run by moving it out of the disabled `homelab.services.backup` module into the postgres module, with dumps on Nitor.

**Files:**
- Modify: `homelab/services/postgresql/default.nix`
- Modify: `homelab/services/backup/default.nix`

**Acceptance Criteria:**
- [ ] After deploy, `systemctl list-timers postgresqlBackup-*.timer` shows active timers for every postgres-backed service (nextcloud, plausible, paperless, bugsink, …).
- [ ] Manually triggering one (`sudo systemctl start postgresqlBackup-nextcloud.service`) produces a `.sql.gz` file in `/mnt/Nitor/Backups/postgresql/`.
- [ ] The disabled `homelab.services.backup` module no longer references `services.postgresqlBackup` (single source of truth).

**Verify:** `just check` passes; after deploy: `ls /mnt/Nitor/Backups/postgresql/` shows dump files for ensured databases.

**Steps:**

- [ ] **Step 1: Replace `homelab/services/postgresql/default.nix`**

```nix
{ config, lib, ... }:
let
  homelab = config.homelab;
  dataDir = "${homelab.mounts.config}/postgresql/${config.services.postgresql.package.psqlSchema}";
  backupDir = "${homelab.mounts.Nitor}/Backups/postgresql";
in
{
  config = lib.mkIf config.services.postgresql.enable {
    services.postgresql = {
      inherit dataDir;
    };

    services.postgresqlBackup = {
      enable = true;
      databases = config.services.postgresql.ensureDatabases;
      location = backupDir;
    };

    systemd.services.postgresql.serviceConfig = {
      ReadWritePaths = [ dataDir ];
    };

    systemd.tmpfiles.rules = [
      "d ${backupDir} 0700 postgres postgres -"
    ];

    environment.persistence."/".directories = [
      {
        directory = dataDir;
        user = "postgres";
        group = "postgres";
        mode = "0700";
      }
    ];
  };
}
```

- [ ] **Step 2: Remove the `services.postgresqlBackup` block from `homelab/services/backup/default.nix`**

Delete lines 55–58 in `homelab/services/backup/default.nix` (the `services.postgresqlBackup` attrset). Keep `services.mysqlBackup` and `services.borgbackup.jobs` as-is. The resulting block (the relevant portion) should look like:

```nix
config = lib.mkIf cfg.enable {
  systemd.tmpfiles.rules = [
    "d ${cfg.repoPath} 0775 ${hl.user} ${hl.group} -"
    "d ${cfg.configBackup.target} 0775 ${hl.user} ${hl.group} -"
  ];

  # Keep the built-in DB backup services alive if they are in use
  services.mysqlBackup = {
    enable = config.services.mysql.enable;
    databases = config.services.mysql.ensureDatabases;
  };

  services.borgbackup.jobs = {
    # …unchanged…
  };
};
```

- [ ] **Step 3: Validate the flake**

Run: `just check`
Expected: no errors.

- [ ] **Step 4: Dry-run the deploy**

Run: `just dry-run magic-pylon`
Expected: outputs the diff of activations including `postgresqlBackup-*.service` and `postgresqlBackup-*.timer` units being added; no errors.

- [ ] **Step 5: Commit**

```bash
git add homelab/services/postgresql/default.nix homelab/services/backup/default.nix
git commit -m "feat(postgresql): enable postgresqlBackup with dumps to Nitor"
```

---

### Task 1: Add `resendApiKey` agenix secret entry

**Goal:** Reference the encrypted Resend SMTP API key (already placed in nix-private repo) so Stalwart can read it at runtime.

**Files:**
- Modify: `machines/nixos/magic-pylon/secrets/default.nix`

**Acceptance Criteria:**
- [ ] `just check` passes.
- [ ] After deploy, `/run/agenix/resendApiKey` exists and is readable by the `stalwart-mail` user.
- [ ] `sudo cat /run/agenix/resendApiKey` shows a string starting with `re_`.

**Verify:** `sudo ls -l /run/agenix/resendApiKey` on magic-pylon after deploy.

**Steps:**

- [ ] **Step 1: Add the secret to `machines/nixos/magic-pylon/secrets/default.nix`**

Insert one new line in the `age.secrets` block. Resulting file:

```nix
{ inputs, ... }:
{
  age.secrets = {
    paperlessPassword.file = "${inputs.secrets}/paperlessPassword.age";
    nextcloudAdminPassword.file = "${inputs.secrets}/nextcloudAdminPassword.age";
    codeServerPassword.file = "${inputs.secrets}/codeServerPassword.age";
    codeServerSudoPassword.file = "${inputs.secrets}/codeServerSudoPassword.age";
    githubPackagesToken.file = "${inputs.secrets}/githubPackagesToken.age";
    tailscaleAuthKey.file = "${inputs.secrets}/tailscaleAuthKey.age";
    traktClientId.file = "${inputs.secrets}/traktClientId.age";
    traktClientSecret.file = "${inputs.secrets}/traktClientSecret.age";
    plausibleSecretKeybase.file = "${inputs.secrets}/plausibleSecretKeybase.age";
    bugsinkEnv.file = "${inputs.secrets}/bugsinkEnv.age";
    resendApiKey.file = "${inputs.secrets}/resendApiKey.age";
  };
}
```

- [ ] **Step 2: Bump the `secrets` flake input** (in case the local lockfile is stale relative to nix-private's `main`)

Run: `nix flake lock --update-input secrets`
Expected: lockfile updates to the latest commit on `main` of nix-private.

- [ ] **Step 3: Validate the flake**

Run: `just check`
Expected: no errors. If you get "file not found" for `resendApiKey.age`, the precondition (the file exists in nix-private) is not met — fix that first.

- [ ] **Step 4: Commit**

```bash
git add machines/nixos/magic-pylon/secrets/default.nix flake.lock
git commit -m "chore(secrets): add resendApiKey agenix entry"
```

(Don't deploy yet — the secret has no consumer until Task 2 lands.)

---

### Task 2: Add Stalwart NixOS service module

**Goal:** Add the `homelab.services.stalwart` module, import it, and enable it on magic-pylon. After this task the flake builds; deploy happens in Task 3.

**Files:**
- Create: `homelab/services/stalwart/default.nix`
- Modify: `homelab/services/default.nix`
- Modify: `machines/nixos/magic-pylon/homelab/default.nix`

**Acceptance Criteria:**
- [ ] `just check` passes.
- [ ] `just dry-run magic-pylon` shows `stalwart-mail.service` being activated, a `mail.magicsk.eu` and `stalwart.magicsk.eu` Caddy vhost being added, a `stalwart` PG database/user being ensured, and ports 25/465/587/143/993 being opened in the firewall.
- [ ] No nix evaluation errors related to stalwart settings keys.

**Verify:** `just check && just dry-run magic-pylon` outputs without errors and includes the expected unit activations.

**Steps:**

- [ ] **Step 1: Create `homelab/services/stalwart/default.nix`**

```nix
{ config, lib, pkgs, ... }:
let
  service = "stalwart";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;

  publicHost = "mail.${homelab.baseDomain}";
  adminHost  = "${service}.${homelab.baseDomain}";

  dbName = service;
  dbUser = service;
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
        };

        directory."internal" = { type = "internal"; store = "pg"; };

        queue.outbound.next-hop = [
          { "if" = "rcpt_domain != '${cfg.primaryDomain}'"; "then" = "'resend'"; }
          { else = false; }
        ];
        remote."resend" = {
          address = "smtp.resend.com";
          port = 465;
          protocol = "smtp";
          tls.implicit = true;
          auth = {
            username = "resend";
            secret   = "%{file:${cfg.resendApiKeyFile}}%";
          };
        };

        session.auth = {
          mechanisms = [ "PLAIN" "LOGIN" ];
          directory = "'internal'";
          require = [
            { "if" = "listener == 'submission' || listener == 'submissions'"; "then" = true; }
            { else = false; }
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
    users.users.stalwart-mail.extraGroups = [ config.services.caddy.group ];

    # NOTE: As actually implemented in commit `44347ea`, the Resend secret is passed
    # via `services.stalwart-mail.credentials.resendApiKey = toString cfg.resendApiKeyFile`
    # and the settings reference `%{file:/run/credentials/stalwart-mail.service/resendApiKey}%`
    # instead of the agenix path. systemd LoadCredential reads the agenix file as root
    # and exposes it as a per-unit credential — no `age.secrets.resendApiKey.owner` needed.

    environment.persistence."/".directories = [
      { directory = cfg.dataDir; user = "stalwart-mail"; group = "stalwart-mail"; mode = "0750"; }
    ];

    systemd.services.stalwart-mail = {
      after    = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
    };
  };
}
```

- [ ] **Step 2: Add `./stalwart` to `homelab/services/default.nix` imports**

In `homelab/services/default.nix`, locate the `imports = [ … ]` block at the bottom (lines 143–181) and add `./stalwart` in alphabetical order (between `./redis` and `./trakt-backup`):

```nix
  imports = [
    ./affine
    ./arr/prowlarr
    # ./arr/bazarr
    ./arr/jellyseerr
    ./arr/sonarr
    ./arr/radarr
    #./arr/lidarr
    # ./audiobookshelf
    ./backup
    ./borg-ui
    ./bugsink
    ./claude-wrapper
    ./code-server
    ./esphome
    ./flaresolverr
    ./go2rtc
    ./homeassistant
    ./homepage
    ./immich
    ./jellyfin
    ./matter-server
    ./minecraft
    ./mosquitto
    ./nextcloud
    ./obico-ml
    ./open-webui
    ./otbr
    ./paperless-ngx
    ./plausible
    ./postgresql
    ./qbittorrent
    ./redlib
    ./redis
    ./stalwart                                # NEW
    ./trakt-backup
    # ./uptime-kuma
    ./vaultwarden
    ./zigbee2mqtt
  ];
```

- [ ] **Step 3: Enable stalwart on magic-pylon**

Edit `machines/nixos/magic-pylon/homelab/default.nix`. Inside the `services = { … }` block (between `trakt-backup.enable = true;` and the closing `};` on around line 131), add:

```nix
      stalwart = {
        enable = true;
        resendApiKeyFile = config.age.secrets.resendApiKey.path;
      };
```

The resulting tail of the services block:

```nix
      go2rtc.enable = true;
      obico-ml.enable = true;
      trakt-backup.enable = true;
      stalwart = {
        enable = true;
        resendApiKeyFile = config.age.secrets.resendApiKey.path;
      };
    };
  };
}
```

- [ ] **Step 4: Validate the flake**

Run: `just check`
Expected: no errors. If you get "attribute 'queue.outbound.next-hop' missing" or similar from the stalwart-mail module, the TOML key path drifted in nixpkgs `nixos-25.11`. Look at `nixos-search` or `pkgs.stalwart-mail.meta.changelog` for the current schema and adjust the affected attrset. Common drift points: `queue.outbound`, `session.auth.require`, `storage.directory`.

- [ ] **Step 5: Dry-run the deploy**

Run: `just dry-run magic-pylon`
Expected:
- `stalwart-mail.service` listed under units being started
- `caddy.service` reload (new vhost)
- `postgresql.service` reload (new database)
- New firewall ports 25/465/587/143/993

If `nixos-rebuild` errors out, fix the module before committing.

- [ ] **Step 6: Commit**

```bash
git add homelab/services/stalwart/default.nix \
        homelab/services/default.nix \
        machines/nixos/magic-pylon/homelab/default.nix
git commit -m "feat(stalwart): add self-hosted mail server module"
```

---

### Task 3: Deploy and bootstrap Stalwart

**Goal:** Apply the config to magic-pylon, capture the auto-generated admin password, create the internal-only `stalwart.magicsk.eu` DNS, log into the admin UI, rotate the password, and create your mailbox.

**Files:** none (repo unchanged).

**Acceptance Criteria:**
- [ ] `systemctl status stalwart-mail` reports `active (running)` on magic-pylon.
- [ ] Admin UI loads at `https://stalwart.magicsk.eu` from a Tailscale-connected device and rejects access without Tailscale.
- [ ] An admin account exists with a known (rotated) password.
- [ ] A mailbox `you@magicsk.eu` exists (replace `you` with your preferred local-part).
- [ ] The DKIM public key for `default._domainkey.magicsk.eu` is recorded for use in Task 4.

**Verify:** `ssh magic-pylon "systemctl is-active stalwart-mail"` returns `active`; you can log into `https://stalwart.magicsk.eu` and see the mailbox.

**Steps:**

- [ ] **Step 1: Deploy**

Run: `just deploy magic-pylon`
Expected: build completes, switch succeeds.

- [ ] **Step 2: Verify the service is running**

Run: `ssh magic-pylon "sudo systemctl status stalwart-mail --no-pager"`
Expected: `Active: active (running)`.

If it failed to start, capture logs:
```bash
ssh magic-pylon "sudo journalctl -u stalwart-mail --no-pager -n 200"
```
Common causes: TLS cert file unreadable (verify `users.users.stalwart-mail.extraGroups = [ "caddy" ]` took effect and `/var/lib/acme/magicsk.eu/key.pem` is group-readable), PG database not yet created, settings schema mismatch.

- [ ] **Step 3: Capture the auto-generated admin password**

Run: `ssh magic-pylon "sudo journalctl -u stalwart-mail -b | grep -i 'admin' | head -20"`
Expected: a line like `Admin password is: <password>` early in the boot logs.

Copy this password — you'll need it in step 5. If the log line has rotated out of the journal, you can regenerate via the Stalwart CLI:
```bash
ssh magic-pylon "sudo -u stalwart-mail stalwart-cli password admin"
```

- [ ] **Step 4: Add Tailscale-only DNS for `stalwart.magicsk.eu`**

In Cloudflare → `magicsk.eu` zone → DNS, add an `A` record:
- Name: `stalwart`
- IPv4 address: magic-pylon's Tailscale IP (find with `ssh magic-pylon "tailscale ip -4"`)
- Proxy status: **DNS only** (grey cloud, not orange)

Verify from a Tailscale-connected device:
```bash
dig +short stalwart.magicsk.eu
# should return the Tailscale IP
```

From a non-Tailscale device:
```bash
dig +short stalwart.magicsk.eu
# also returns the Tailscale IP, but the IP is unreachable without Tailscale
```

- [ ] **Step 5: Log into the admin UI from Tailscale**

From a Tailscale-connected device, open `https://stalwart.magicsk.eu`. Log in:
- Username: `admin`
- Password: from step 3

If the cert isn't yet trusted, give Caddy a minute to provision the wildcard cert (it should already exist since `*.magicsk.eu` is in the ACME config). Refresh.

- [ ] **Step 6: Rotate the admin password**

In the admin UI: My Account → Change Password → set a strong password. Store it in your password manager.

- [ ] **Step 7: Create your mailbox**

In the admin UI: Management → Accounts → Create new account:
- Type: Individual
- Login: `you` (e.g., `magic_sk` — replace with your preferred local-part)
- Email: `you@magicsk.eu`
- Password: a strong password (this is what IMAP/SMTP clients will use)

- [ ] **Step 8: Generate and record the DKIM key**

In the admin UI: Management → Domains → magicsk.eu → DKIM → Create signing key.
- Algorithm: `ed25519` (smaller, modern) or `rsa-2048` (more compatible — pick this if any concern about older receivers).
- Selector: `default`

After creation, click the key → copy the **public DNS record value**. Save it; you'll add it as a TXT record in Task 4.

The full TXT record will look like:
```
v=DKIM1; k=rsa; p=MIIBIjANBgkqhki…
```

- [ ] **Step 9: No commit (no repo changes).**

---

### Task 4: Cloudflare DNS — inbound mail records

**Goal:** Publish DNS records so the public internet can find your mail server and verify SPF/DKIM/DMARC.

**Files:** none (DNS only).

**Acceptance Criteria:**
- [ ] `dig +short mx magicsk.eu` returns `10 mail.magicsk.eu.`.
- [ ] `dig +short a mail.magicsk.eu` returns `132.226.217.72`.
- [ ] `dig +short txt magicsk.eu` includes the SPF record.
- [ ] `dig +short txt default._domainkey.magicsk.eu` returns the DKIM key.
- [ ] `dig +short txt _dmarc.magicsk.eu` returns the DMARC policy.

**Verify:** Run all `dig` commands above; all return non-empty matching values.

**Steps:**

- [ ] **Step 1: Add the inbound mail records in Cloudflare**

For each row, add a DNS record in `magicsk.eu` zone. **All records below MUST be set to "DNS only" (grey cloud), not proxied (orange cloud)** — proxying breaks SMTP/IMAP traffic.

| Type | Name | Value | TTL |
|---|---|---|---|
| `A` | `mail` | `132.226.217.72` | Auto |
| `MX` | `@` (root) | Mail server: `mail.magicsk.eu`, Priority: `10` | Auto |
| `TXT` | `@` (root) | `v=spf1 ip4:132.226.217.72 include:_spf.resend.com ~all` | Auto |
| `TXT` | `default._domainkey` | *(value from Task 3 step 8 — `v=DKIM1; k=rsa; p=…`)* | Auto |
| `TXT` | `_dmarc` | `v=DMARC1; p=none; rua=mailto:postmaster@magicsk.eu; ruf=mailto:postmaster@magicsk.eu` | Auto |

- [ ] **Step 2: Verify records propagated**

```bash
dig +short mx magicsk.eu
# expected: 10 mail.magicsk.eu.

dig +short a mail.magicsk.eu
# expected: 132.226.217.72

dig +short txt magicsk.eu
# expected: "v=spf1 ip4:132.226.217.72 include:_spf.resend.com ~all"

dig +short txt default._domainkey.magicsk.eu
# expected: "v=DKIM1; k=rsa; p=…"

dig +short txt _dmarc.magicsk.eu
# expected: "v=DMARC1; p=none; rua=mailto:postmaster@magicsk.eu; …"
```

If any record is missing, double-check the name field (Cloudflare often shows the full `name.magicsk.eu` after save — that's normal, the input field accepts the relative name).

- [ ] **Step 3: No commit (no repo changes).**

---

### Task 5: Resend domain verification

**Goal:** Add `magicsk.eu` in the Resend dashboard, copy the verification records into Cloudflare, and confirm Resend reports the domain as Verified.

**Files:** none.

**Acceptance Criteria:**
- [ ] Resend dashboard shows `magicsk.eu` status as "Verified" (all DNS records green).
- [ ] A test send through Resend's SMTP API from any test tool succeeds with status 250.

**Verify:** Resend dashboard "Domains" page shows `magicsk.eu` green/Verified.

**Steps:**

- [ ] **Step 1: Add the domain in Resend**

Go to https://resend.com/domains → Add Domain → enter `magicsk.eu` → Add.

Resend will display 3–5 records to add. Typical shape (your exact values will differ):

| Type | Name | Value |
|---|---|---|
| `TXT` | `send.magicsk.eu` | `v=spf1 include:amazonses.com ~all` |
| `CNAME` | `resend._domainkey.magicsk.eu` | `resend._domainkey.<region>.dkim.amazonses.com` |
| `MX` | `send.magicsk.eu` | `feedback-smtp.<region>.amazonses.com` priority `10` |
| `TXT` | *(verification, sometimes prefixed `_resend.`)* | *(random string)* |

- [ ] **Step 2: Copy each record into Cloudflare**

For each row from Resend, create a matching DNS record in Cloudflare `magicsk.eu` zone, **DNS only (grey cloud)**.

Cloudflare quirk: if you already have a CNAME for `resend._domainkey`, delete it before adding the new one. Cloudflare won't allow two records with the same name.

- [ ] **Step 3: Trigger verification in Resend**

Back in the Resend dashboard → Domain → "Verify DNS Records". Status should turn green within 1–2 minutes (sometimes longer for slow DNS providers; Cloudflare propagates fast).

- [ ] **Step 4: No commit (no repo changes).**

---

### Task 6: Oracle VPS — iptables port forwarding

**Goal:** Forward mail ports from the VPS public IP through wg0 to magic-pylon. After this task, external clients can reach Stalwart on `mail.magicsk.eu`.

**Files:** none.

**Acceptance Criteria:**
- [ ] `nc -vz mail.magicsk.eu 25` from your laptop (off-LAN) connects.
- [ ] `nc -vz mail.magicsk.eu 993` from your laptop (off-LAN) connects.
- [ ] `sudo iptables -t nat -L PREROUTING -n -v` on the VPS shows DNAT rules for ports 25/465/587/143/993.

**Verify:** Above netcat commands connect successfully from outside your LAN/Tailscale.

**Steps:**

- [ ] **Step 1: SSH into the VPS**

```bash
ssh <your-user>@132.226.217.72
```

(Use whatever credentials/key you currently use for the VPS.)

- [ ] **Step 2: Enable IP forwarding persistently**

```bash
sudo sh -c 'echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-mail-forward.conf'
sudo sysctl --system
```

Verify: `sudo sysctl net.ipv4.ip_forward` returns `net.ipv4.ip_forward = 1`.

- [ ] **Step 3: Identify the public interface name**

```bash
ip -br a
```

Look for the interface with the public IPv4 (`132.226.217.72/…`). Typical names: `ens3`, `enp0s3`. Set a variable:

```bash
IFACE=<the_name>   # e.g. IFACE=ens3
```

- [ ] **Step 4: Verify the WireGuard peer**

```bash
sudo wg show
```

Confirm the peer corresponding to magic-pylon has `allowed ips: 172.16.16.2/32` (or a wider range that includes it). If not, fix the WG config first — the DNAT will silently fail otherwise.

- [ ] **Step 5: Add iptables rules**

```bash
# Allow inbound on the mail ports
sudo iptables -A INPUT -p tcp -m multiport --dports 25,465,587,143,993 -j ACCEPT

# DNAT each mail port to magic-pylon's wg0 address
for P in 25 465 587 143 993; do
  sudo iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$P" \
    -j DNAT --to-destination 172.16.16.2:"$P"
done

# Allow forwarded traffic into wg0
sudo iptables -A FORWARD -i "$IFACE" -o wg0 -d 172.16.16.2 \
  -p tcp -m multiport --dports 25,465,587,143,993 -j ACCEPT
sudo iptables -A FORWARD -i wg0 -o "$IFACE" \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Masquerade replies so the source IP at magic-pylon is wg0's IP, not the original sender
sudo iptables -t nat -A POSTROUTING -o wg0 -d 172.16.16.2 -j MASQUERADE
```

- [ ] **Step 6: Verify rules are present**

```bash
sudo iptables -t nat -L PREROUTING -n -v
sudo iptables -L FORWARD -n -v
```

Expected: DNAT entries for each mail port, FORWARD rules visible.

- [ ] **Step 7: Persist rules across reboots**

**Ubuntu / Debian:**
```bash
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save
```

**Oracle Linux / RHEL:**
```bash
sudo dnf install -y iptables-services
sudo systemctl enable --now iptables
sudo service iptables save
```

Pick the one that matches your VPS. Verify the rules are written to `/etc/iptables/rules.v4` (Ubuntu) or `/etc/sysconfig/iptables` (RHEL).

- [ ] **Step 8: Test from outside (after Task 7 also done)**

The full external test requires the OCI Security List from Task 7 to also be open. Don't run this test in isolation — defer to the end of Task 7.

- [ ] **Step 9: No commit (no repo changes).**

---

### Task 7: Oracle Cloud Console — Security List and PTR

**Goal:** Open the mail ports at the cloud-firewall layer and set reverse DNS so deliverability works.

**Files:** none.

**Acceptance Criteria:**
- [ ] OCI VCN Security List for the VPS subnet has ingress rules for TCP `25, 465, 587, 143, 993` from `0.0.0.0/0`.
- [ ] `dig -x 132.226.217.72` returns `mail.magicsk.eu`.
- [ ] `nc -vz mail.magicsk.eu 25` from your laptop (off-LAN) succeeds.

**Verify:** The `nc -vz` and `dig -x` commands above succeed.

**Steps:**

- [ ] **Step 1: Open Security List rules**

OCI Console → Networking → Virtual Cloud Networks → your VCN → Security Lists → the list attached to the VPS's subnet → Add Ingress Rules.

Add 5 rules (one per port — or one with port range if your list supports it):

| Source CIDR | IP Protocol | Source Port Range | Destination Port |
|---|---|---|---|
| `0.0.0.0/0` | TCP | (blank) | `25` |
| `0.0.0.0/0` | TCP | (blank) | `465` |
| `0.0.0.0/0` | TCP | (blank) | `587` |
| `0.0.0.0/0` | TCP | (blank) | `143` |
| `0.0.0.0/0` | TCP | (blank) | `993` |

Save.

- [ ] **Step 2: Set PTR (reverse DNS)**

OCI Console → Compute → Instances → your VPS → Attached VNICs → primary VNIC → Edit (or "Internet & VCN" section, depending on console version) → Hostname field → set to `mail.magicsk.eu` → Save.

OCI takes a few minutes to propagate.

- [ ] **Step 3: Verify PTR**

```bash
dig -x 132.226.217.72
# expected: ;; ANSWER SECTION: 217.72.226.132.in-addr.arpa. … PTR mail.magicsk.eu.
```

If still showing the default `oracleinternalcustomer…` name after 10 minutes, double-check the hostname field was saved and the VCN's DHCP options haven't overridden it.

- [ ] **Step 4: End-to-end port test from outside**

From your laptop (must be off-LAN and not connected to Tailscale):

```bash
nc -vz mail.magicsk.eu 25     # banner: 220 mail.magicsk.eu Stalwart … ESMTP
nc -vz mail.magicsk.eu 465    # connection succeeds, TLS handshake
nc -vz mail.magicsk.eu 587    # banner with STARTTLS
nc -vz mail.magicsk.eu 143    # banner
nc -vz mail.magicsk.eu 993    # connection succeeds, TLS handshake
```

If any fails, work backwards: check Security List → iptables (`sudo iptables -t nat -L PREROUTING -n -v` for hit counts) → Stalwart (`ssh magic-pylon "ss -tlnp | grep -E ':(25|465|587|143|993)\b'"`).

- [ ] **Step 5: No commit (no repo changes).**

---

### Task 8: End-to-end deliverability verification

**Goal:** Prove the full system works — send/receive real mail, get a passing deliverability score, configure an IMAP client.

**Files:** none.

**Acceptance Criteria:**
- [ ] Test mail sent from `you@magicsk.eu` to a personal Gmail/Outlook account arrives in **inbox** (not spam) with headers `dkim=pass spf=pass dmarc=pass`.
- [ ] Test mail sent from Gmail/Outlook to `you@magicsk.eu` arrives in your IMAP client within 30 seconds.
- [ ] `mail-tester.com` score is `≥ 8/10`.
- [ ] An IMAP client (Thunderbird, Apple Mail, etc.) is configured against `mail.magicsk.eu` with TLS and successfully sends + receives.

**Verify:** All four boxes above check out.

**Steps:**

- [ ] **Step 1: Configure an IMAP client**

In Thunderbird (or your client of choice), add an account:
- Display name: your name
- Email: `you@magicsk.eu`
- Password: the password set in Task 3 step 7

Manual config (if auto-detect fails):
- IMAP host: `mail.magicsk.eu`, port `993`, SSL/TLS
- SMTP host: `mail.magicsk.eu`, port `465`, SSL/TLS
- Auth: Normal password
- Username: `you@magicsk.eu` (full email)

Verify the inbox connects (Stalwart's default mailboxes appear: INBOX, Sent, Drafts, Trash).

- [ ] **Step 2: Send a mail to your existing Gmail/Outlook**

Compose → To: `<your-existing-gmail>` → Subject: `stalwart test outbound` → Body: any text → Send.

In Gmail, check:
- Did it arrive in **inbox** (not spam)?
- Open the message → click "Show Original" → scroll to the headers
- Verify `Authentication-Results:` shows `dkim=pass`, `spf=pass`, `dmarc=pass`.
- The `Received-SPF` line should reference `_spf.resend.com` (since outbound goes through Resend).

If `dkim=fail` for the *Resend* DKIM (resend._domainkey), the Resend records from Task 5 aren't right.
If `spf=fail`, check your TXT record on `magicsk.eu` (apex) matches Task 4 exactly.

- [ ] **Step 3: Reply from Gmail → you@magicsk.eu**

Reply to the message you just sent. Check:
- Does it arrive in your IMAP client?
- Is the `Received-SPF` and `Authentication-Results` for Gmail's sending IP (your *server* validated the inbound message, not Resend).

- [ ] **Step 4: Test with mail-tester.com**

Open https://www.mail-tester.com → it gives you a random address like `test-abc123@mail-tester.com` → send a test mail to it from `you@magicsk.eu` → click "Then check your score".

Expected score: ≥ 8/10. Typical deductions: missing DANE/TLSA (optional, fine to ignore), MTA-STS not published (optional), domain age (you can't fix this), no list-unsubscribe header for newsletters (irrelevant for personal mail).

- [ ] **Step 5: Smoke test: restart the service, mail still works**

```bash
ssh magic-pylon "sudo systemctl restart stalwart-mail"
```

Wait 10 seconds, then send another mail to yourself and confirm it arrives. This catches any first-run-only config that didn't persist.

- [ ] **Step 6: No commit (no repo changes).**

- [ ] **Step 7: Update the homepage if desired**

If you want Stalwart's admin UI tile on `lab.magicsk.eu`, the `homepage.*` options in the stalwart module already set its name/icon/category. Just verify it appears next time you load the homepage.

If the `stalwart.svg` icon isn't present in homepage-dashboard's icon set, fall back to `mdi-email-edit` or another available icon (edit `homepage.icon` in Task 2's module to override the default).

---

## Out of scope (separate follow-ups)

- Flipping `firewall.enable = true` on magic-pylon (requires auditing all services that bind to non-loopback)
- Webmail UI (Roundcube / SnappyMail)
- Additional mail domains beyond `magicsk.eu`
- Tightening DMARC from `p=none` to `p=quarantine` (do once deliverability is stable for a few weeks)
- DANE/TLSA records for highest-grade deliverability
- Migrating existing mail from another provider (`imapsync` job, manual)

## Rollback

If something is irrecoverably broken and you want to back out:

1. Revert the commits from tasks 0, 1, 2: `git revert HEAD~N..HEAD` (where N is the number of commits, typically 3).
2. `just deploy magic-pylon` — Stalwart service is removed, PostgreSQL `stalwart` database orphaned but harmless.
3. Optionally drop the orphan database: `ssh magic-pylon "sudo -u postgres psql -c 'DROP DATABASE stalwart; DROP USER stalwart;'"`.
4. Remove DNS records added in Tasks 4 and 5 (Cloudflare).
5. Remove iptables rules from Task 6 (`sudo iptables -F` plus persistent file edit, or just reboot the VPS if rules weren't yet persisted).
6. Remove OCI Security List ingress rules from Task 7.
7. Mail data at `/persist/opt/services/stalwart/blobs/` remains until you `sudo rm -rf` it; the PG dumps remain at `/mnt/Nitor/Backups/postgresql/` until pruned.
