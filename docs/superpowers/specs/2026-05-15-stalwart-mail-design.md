# Stalwart Mail Server on magic-pylon — Design Spec

**Date:** 2026-05-15
**Author:** magicsk (with Claude)
**Status:** Approved design, ready for implementation plan

## Goal

Self-host email on the homelab. Replace dependence on free mail providers. Address: `<user>@magicsk.eu`. Stable enough for personal and light business use, but with hobby-grade operational expectations (no HA, single-host, manual VPS runbook).

## Scope

In scope:

- Deploy [Stalwart Mail Server](https://stalw.art/) on `magic-pylon` as a new homelab service module
- Inbound mail via existing Oracle VPS (`132.226.217.72`) port-forwarded over WireGuard to magic-pylon
- Outbound mail via [Resend](https://resend.com/) SMTP relay (free tier: 100/day, 3000/month)
- IMAP/SMTPS access from outside the LAN
- Admin UI on a Tailscale-only hostname; SMTP/IMAP on a public hostname
- TLS certs reused from existing wildcard ACME (`security.acme.certs."magicsk.eu"`)
- PostgreSQL backend for metadata (reuses existing `services.postgresql`), filesystem for blobs
- Relocate `services.postgresqlBackup.location` to `${hl.mounts.Nitor}/Backups/postgresql` so PG dumps survive reboots; borg coverage of that folder is managed externally via borg-ui

Out of scope:

- Webmail (Roundcube / SnappyMail) — deferred; IMAP clients only
- Multi-domain mail — single primary domain `magicsk.eu`
- HA / failover MX
- DANE / TLSA records (advanced deliverability, may add later)
- Flipping `firewall.enable = true` on magic-pylon — tracked as separate follow-up; requires auditing all other services first

## Architecture

```
                       ┌──────────────────────────────────────────────────┐
                       │  Public Internet                                 │
                       │  (Gmail, Outlook, IMAP clients on the road, …)   │
                       └─────────────────┬────────────────────────────────┘
                                         │
                       Inbound mail :25  │ Outbound mail (DKIM-signed by Resend)
                                         │
                       ┌─────────────────▼────────────────────────────────┐
                       │  Oracle VPS (132.226.217.72) — "front door"      │
                       │  • iptables DNAT :25/465/587/143/993 → wg0       │
                       │  • PTR: 132.226.217.72 → mail.magicsk.eu         │
                       │  • OCI Security List allows inbound on those     │
                       └─────────────────┬────────────────────────────────┘
                                         │
                                         │ WireGuard wg0 (172.16.16.0/24)
                                         │
   ┌─────────────────────────────────────▼────────────────────────────────┐
   │  magic-pylon (NixOS)                                                 │
   │                                                                      │
   │   ┌────────────────────────────────┐                                 │
   │   │ services.stalwart-mail          │   metadata  ┌──────────────┐  │
   │   │  • SMTP :25, :465, :587         │────────────▶│ PostgreSQL   │  │
   │   │  • IMAP :143, :993              │             │ db=stalwart  │  │
   │   │  • HTTP :8080 (loopback only)   │             │ (peer auth)  │  │
   │   │                                 │             └──────────────┘  │
   │   │                                 │   blobs                       │
   │   │                                 │────────────▶ /persist/opt/    │
   │   │                                 │              services/        │
   │   │                                 │              stalwart/blobs   │
   │   │                                 │                               │
   │   │  TLS certs: shared with caddy   │   outbound                    │
   │   │  /var/lib/acme/magicsk.eu/      │────────────▶ smtp.resend.com  │
   │   └──────────────┬──────────────────┘              :465 (auth)      │
   │                  │                                                  │
   │                  │ HTTP :8080                                       │
   │                  ▼                                                  │
   │   ┌────────────────────────────────┐                                │
   │   │ Caddy                           │──▶ stalwart.magicsk.eu (HTTPS)│
   │   │ wildcard *.magicsk.eu cert      │   (admin UI / JMAP, internal) │
   │   └────────────────────────────────┘                                │
   └──────────────────────────────────────────────────────────────────────┘
```

## Components

### New files

- `homelab/services/stalwart/default.nix` — the service module

### Modified files

- `homelab/services/default.nix` — add `./stalwart` to imports
- `machines/nixos/magic-pylon/homelab/default.nix` — enable `stalwart` with `resendApiKeyFile`
- `machines/nixos/magic-pylon/secrets/default.nix` — add `resendApiKey` agenix entry
- `homelab/services/postgresql/default.nix` — enable `services.postgresqlBackup` (currently gated behind the disabled `homelab.services.backup` module) with `location` on Nitor
- `homelab/services/backup/default.nix` — remove the now-redundant `services.postgresqlBackup` block

### External

- `${inputs.secrets}/resendApiKey.age` — encrypted Resend SMTP key (`re_…`), prepared in nix-private repo
- Cloudflare DNS records — see "DNS records" below
- Oracle VPS iptables + PTR — see "VPS runbook" below
- Resend dashboard — add `magicsk.eu`, copy verification records into Cloudflare

## NixOS service module (`homelab/services/stalwart/default.nix`)

Follows the existing service-module pattern (options + `mkIf cfg.enable`):

```nix
{ config, lib, pkgs, ... }:
let
  service = "stalwart";
  cfg = config.homelab.services.${service};
  homelab = config.homelab;

  publicHost = "mail.${homelab.baseDomain}";     # MX + SMTP/IMAP (public DNS)
  adminHost  = "${service}.${homelab.baseDomain}"; # admin UI (Tailscale-only DNS)

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
      default = adminHost;       # homepage tile points at the admin UI
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
        # TLS — share Caddy's wildcard cert
        certificate.default = {
          cert        = "%{file:/var/lib/acme/${homelab.baseDomain}/fullchain.pem}%";
          private-key = "%{file:/var/lib/acme/${homelab.baseDomain}/key.pem}%";
          default     = true;
        };

        # Listeners
        server.listener = {
          smtp         = { bind = [ "[::]:25"  ]; protocol = "smtp"; };
          submissions  = { bind = [ "[::]:465" ]; protocol = "smtp"; tls.implicit = true; };
          submission   = { bind = [ "[::]:587" ]; protocol = "smtp"; };
          imap         = { bind = [ "[::]:143" ]; protocol = "imap"; };
          imaps        = { bind = [ "[::]:993" ]; protocol = "imap"; tls.implicit = true; };
          http         = { bind = [ "127.0.0.1:8080" ]; protocol = "http"; };
        };

        # Storage — PG metadata, FS blobs
        store."pg"      = { type = "postgresql"; host = "/run/postgresql"; database = dbName; user = dbUser; };
        store."blob-fs" = { type = "fs";         path = "${cfg.dataDir}/blobs"; };
        storage = {
          data = "pg"; blob = "blob-fs"; fts = "pg"; lookup = "pg"; directory = "internal";
        };

        directory."internal" = { type = "internal"; store = "pg"; };

        # Outbound — anything not @primaryDomain goes through Resend
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

        # AUTH required on submission ports; anonymous on :25 (MX)
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

    # PostgreSQL — local user/db, peer auth via socket
    services.postgresql = {
      ensureDatabases = [ dbName ];
      ensureUsers = [{ name = dbUser; ensureDBOwnership = true; }];
    };

    # Caddy — reverse proxy admin UI to internal HTTP only
    services.caddy.virtualHosts."${adminHost}" = {
      useACMEHost = homelab.baseDomain;
      extraConfig = ''
        reverse_proxy http://127.0.0.1:8080
      '';
    };

    # Firewall (informational while firewall.enable=false; needed once flipped)
    networking.firewall.allowedTCPPorts = [ 25 465 587 143 993 ];

    # Share the wildcard cert with stalwart on renewal
    security.acme.certs."${homelab.baseDomain}".reloadServices = [
      "caddy.service"
      "stalwart-mail.service"
    ];
    users.users.stalwart-mail.extraGroups = [ config.services.caddy.group ];

    # Impermanence
    environment.persistence."/".directories = [
      { directory = cfg.dataDir; user = "stalwart-mail"; group = "stalwart-mail"; mode = "0750"; }
    ];

    # Ordering: postgres up before stalwart
    systemd.services.stalwart-mail = {
      after    = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
    };
  };
}
```

### Wiring

`homelab/services/default.nix` — add `./stalwart` to the `imports` list.

`machines/nixos/magic-pylon/homelab/default.nix` — add inside `homelab.services`:

```nix
stalwart = {
  enable = true;
  resendApiKeyFile = config.age.secrets.resendApiKey.path;
};
```

`machines/nixos/magic-pylon/secrets/default.nix` — add:

```nix
resendApiKey.file = "${inputs.secrets}/resendApiKey.age";
```

### Key design choices

1. **Storage split:** PostgreSQL for metadata/FTS/directory (small, transactional, benefits from PG dumps); filesystem for blobs (large, hot-path, already in the borg job).
2. **TLS cert reuse:** Stalwart reads the same wildcard cert files as Caddy at `/var/lib/acme/magicsk.eu/`. `security.acme.certs.…reloadServices` reloads both daemons on renewal. Stalwart user is added to the `caddy` group for read access.
3. **Outbound relay scoping:** `queue.outbound.next-hop` routes mail only when `rcpt_domain != magicsk.eu`. Internal mail stays local even if Resend is down.
4. **Auth boundary:** SMTP submission ports require AUTH; port 25 (MX inbound) does not. IMAP ports always require AUTH.
5. **Public/private split:** `mail.magicsk.eu` is the public hostname (must be — for MX). The admin UI is moved to `stalwart.magicsk.eu` and gated by Tailscale-only DNS.

### Stalwart config syntax caveat

The `queue.outbound.next-hop`, `session.auth.require`, etc. expression syntax above is conceptually correct for current Stalwart releases but exact key paths can shift between versions. The implementation step will pin to a specific Stalwart version (likely `pkgs.stalwart-mail` from the channel matching this flake's `nixos-unstable`) and verify the keys against that release's docs before merging.

## DNS records (manual in Cloudflare)

### Inbound mail (mandatory)

| Type | Name | Value | Notes |
|---|---|---|---|
| `A` | `mail.magicsk.eu` | `132.226.217.72` | VPS public IP |
| `AAAA` | `mail.magicsk.eu` | *(VPS IPv6 if available)* | Optional |
| `MX` | `magicsk.eu` | `10 mail.magicsk.eu.` | |
| `TXT` | `magicsk.eu` | `v=spf1 ip4:132.226.217.72 include:_spf.resend.com ~all` | SPF |
| `TXT` | `default._domainkey.magicsk.eu` | *(from Stalwart after first start)* | DKIM |
| `TXT` | `_dmarc.magicsk.eu` | `v=DMARC1; p=none; rua=mailto:postmaster@magicsk.eu` | Tighten to `p=quarantine` once stable |
| `TXT` | `_mta-sts.magicsk.eu` | `v=STSv1; id=20260515000000` | Optional |
| `TXT` | `_smtp._tls.magicsk.eu` | `v=TLSRPTv1; rua=mailto:postmaster@magicsk.eu` | Optional |

### Resend records (values supplied by Resend dashboard)

After adding `magicsk.eu` in Resend's dashboard, copy the records it shows. Typical shape:

| Type | Name | Value |
|---|---|---|
| `TXT` | `send.magicsk.eu` | `v=spf1 include:amazonses.com ~all` |
| `CNAME` | `resend._domainkey.magicsk.eu` | `resend._domainkey.<…>.dkim.amazonses.com` |
| `MX` | `send.magicsk.eu` | `10 feedback-smtp.<region>.amazonses.com.` |
| `TXT` | *(domain verification)* | *(random string)* |

### Internal-only (no public DNS)

| Type | Name | Value | Notes |
|---|---|---|---|
| `A` | `stalwart.magicsk.eu` | *(Tailscale or LAN IP of magic-pylon)* | Admin UI only |

### Already exist (no change)

`CAA` records for ACME, wildcard `*.magicsk.eu`.

### Order of operations

1. Deploy Stalwart and capture the DKIM public key from the admin UI.
2. Add inbound records (without DKIM).
3. Add DKIM TXT once Stalwart has the keypair.
4. Add `magicsk.eu` in the Resend dashboard, paste their records into Cloudflare.
5. Verify Resend shows "Verified".
6. Verify externally: `dig mx magicsk.eu`, `dig txt magicsk.eu`, `dig -x 132.226.217.72`.

## VPS runbook (iptables, manual one-time)

### 1. Enable IP forwarding (persistent)

```bash
sudo sh -c 'echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-mail-forward.conf'
sudo sysctl --system
```

### 2. iptables rules

```bash
IFACE=ens3   # replace with output of `ip -br a` for the public NIC

# Allow inbound
sudo iptables -A INPUT -p tcp -m multiport --dports 25,465,587,143,993 -j ACCEPT

# DNAT to magic-pylon
for P in 25 465 587 143 993; do
  sudo iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$P" \
    -j DNAT --to-destination 172.16.16.2:"$P"
done

# Forward into wg0
sudo iptables -A FORWARD -i "$IFACE" -o wg0 -d 172.16.16.2 \
  -p tcp -m multiport --dports 25,465,587,143,993 -j ACCEPT
sudo iptables -A FORWARD -i wg0 -o "$IFACE" \
  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Masquerade replies
sudo iptables -t nat -A POSTROUTING -o wg0 -d 172.16.16.2 -j MASQUERADE
```

### 3. Persist rules

Ubuntu/Debian:
```bash
sudo apt install iptables-persistent
sudo netfilter-persistent save
```

Oracle Linux/RHEL:
```bash
sudo dnf install iptables-services
sudo systemctl enable --now iptables
sudo service iptables save
```

### 4. OCI Security List

In OCI Console → VCN → Security Lists → default — add ingress rules for TCP `25, 465, 587, 143, 993` from `0.0.0.0/0`. Without this, traffic is dropped at the cloud edge before reaching iptables.

### 5. Reverse DNS (PTR)

OCI Console → Compute → instance → Attached VNICs → primary VNIC → Edit → Hostname = `mail.magicsk.eu`. Verify with `dig -x 132.226.217.72`.

### 6. Verify end-to-end

```bash
# from your laptop
nc -vz mail.magicsk.eu 25      # connects, banner shows Stalwart
nc -vz mail.magicsk.eu 993     # connects, TLS handshake possible
dig mx magicsk.eu              # 10 mail.magicsk.eu.
dig -x 132.226.217.72          # mail.magicsk.eu
```

### 7. Deliverability check

Send a test to:
- `check-auth@verifier.port25.com` — emails back a detailed SPF/DKIM/DMARC report
- A throwaway Gmail (inbox AND spam)
- `mail-tester.com` — score out of 10

### Prerequisites to verify before running the runbook

- Public iface name on the VPS (likely `ens3`, confirm with `ip -br a`)
- magic-pylon's `172.16.16.2/32` is in the VPS-side wg0 peer's `AllowedIPs` (`wg show` to confirm)

## Backup integration

This repo's `homelab.services.backup` nix module is intentionally disabled — backup jobs are managed via **borg-ui** out-of-band. So no automatic borg coverage is added by this change. What this change *does* do is make sure stalwart's persistent data lives where borg-ui can pick it up:

- **Mail blobs** at `/persist/opt/services/stalwart/blobs/` — already on a persistent path; include this folder in your borg-ui job set.
- **Live PG data** at `/persist/opt/services/postgresql/<schema>/` — already in your borg-ui scope (presumably, alongside other services).
- **PG logical dumps** → relocated from default `/var/backup/postgresql/` to `${hl.mounts.Nitor}/Backups/postgresql` (see snippet below). This is the only nix-side change required for backup; borg-ui can mirror that folder to Alumentum on whatever cadence you've configured there.
- **DKIM private key** → stored in PG `stalwart` database → captured by both the live PG dir and the logical dumps.

### Enable PG dumps independently of the disabled backup module

Today `services.postgresqlBackup` is configured inside `homelab/services/backup/default.nix` under `lib.mkIf cfg.enable`, so it's *not* running. Move it into the postgres module (`homelab/services/postgresql/default.nix`) so it runs whenever postgres is enabled:

```nix
# in homelab/services/postgresql/default.nix, inside `config = lib.mkIf …`
services.postgresqlBackup = {
  enable    = true;
  databases = config.services.postgresql.ensureDatabases;
  location  = "${homelab.mounts.Nitor}/Backups/postgresql";
};

systemd.tmpfiles.rules = [
  # …existing tmpfiles rules…
  "d ${homelab.mounts.Nitor}/Backups/postgresql 0700 postgres postgres -"
];

environment.persistence."/".directories = [
  # …existing…
  { directory = "${homelab.mounts.Nitor}/Backups/postgresql"; user = "postgres"; group = "postgres"; mode = "0700"; }
];
```

Also remove the now-redundant `services.postgresqlBackup` block from `homelab/services/backup/default.nix` so the configuration has a single source of truth.

> Note: This will now also produce nightly logical dumps for nextcloud, plausible, paperless, bugsink, and any other postgres-backed service — not just stalwart. That's a positive side effect (you previously had no logical dumps for any of them), but mentioning so you can opt out of any specific database via `databases = lib.filter (d: d != "foo") config.services.postgresql.ensureDatabases` if needed.

> **Operator note:** Nitor is 2× HDD RAID0 (no redundancy). Make sure your borg-ui setup mirrors `${hl.mounts.Nitor}/Backups/postgresql` to Alumentum so dumps survive a single Nitor drive failure.

### Restore drill

1. Restore `/persist/opt/services/stalwart/` from your borg-ui repository.
2. Restore PG `stalwart` database from the latest `postgresqlBackup` dump (`gunzip -c /mnt/Nitor/Backups/postgresql/stalwart.sql.gz | psql stalwart`).
3. `systemctl restart stalwart-mail`.
4. Verify admin UI loads and a test mail arrives.

## Bootstrap / first-run flow

1. Apply the nix changes (`nixos-rebuild switch` on magic-pylon).
2. `journalctl -u stalwart-mail -b | grep -i 'admin'` — capture the auto-generated admin password.
3. Add Tailscale DNS for `stalwart.magicsk.eu` (record to magic-pylon).
4. Open `https://stalwart.magicsk.eu` from a Tailscale-connected device.
5. Log in as `admin`, rotate the password.
6. Create primary mailbox: `you@magicsk.eu`.
7. In admin UI → DKIM → copy the public key for `default._domainkey.magicsk.eu`.
8. Add the DKIM TXT to Cloudflare.
9. In Resend dashboard, add `magicsk.eu` and copy verification records to Cloudflare.
10. Run the VPS runbook.
11. From an external mail client (e.g., Thunderbird):
    - IMAP: `mail.magicsk.eu:993` (TLS) — username `you@magicsk.eu`
    - SMTP: `mail.magicsk.eu:465` (TLS) — same credentials
12. Send/receive test mails per the deliverability checks.

## Risks and open questions

- **Resend free tier limits** (100/day, 3000/month). For personal mail this is plenty; if exceeded, switch the `remote."resend"` block to a different relay or upgrade Resend. Stalwart config change only.
- **Oracle port 25 outbound** is blocked on free tier; we don't need outbound on the VPS for this design (outbound goes through Resend).
- **Outbound port 465 from VPS** — magic-pylon's traffic to `smtp.resend.com:465` exits via wg0 → VPS → internet. Oracle doesn't block 465/587 in our experience, but verify before relying on it: `nc -vz smtp.resend.com 465` from the VPS. If blocked, we'd need to switch the relay to a port Oracle allows (Resend also offers 2587 and 25, but the latter is blocked too — 587 is the fallback).
- **Stalwart NixOS module schema drift** — exact TOML key paths in `services.stalwart-mail.settings` can change between Stalwart releases; implementation step pins to a specific version and verifies before merge.
- **DKIM key rotation** — Stalwart manages this. Document the rotation flow (regenerate in admin UI → update Cloudflare TXT) before the first rotation is needed.
- **Public admin UI risk** — `stalwart.magicsk.eu` resolving to a Tailscale-only IP relies entirely on DNS discipline. If that record ever gets a public IP, the admin login page becomes internet-facing. Mitigate by setting a strong admin password (we do) and considering an additional Caddy `@internal` matcher in a future hardening pass.

## Testing

Manual, post-implementation:

1. `nixos-rebuild switch` builds successfully and stalwart-mail starts (`systemctl status stalwart-mail`).
2. Admin UI loads at `https://stalwart.magicsk.eu` from Tailscale.
3. Admin UI returns 5xx/timeout from a non-Tailscale device (proves DNS gating works).
4. After VPS runbook: `nc -vz mail.magicsk.eu 25` connects from off-LAN.
5. After DNS: send self → external Gmail, verify inbox delivery (not spam) and headers show `dkim=pass spf=pass dmarc=pass`.
6. External → self: send from Gmail to `you@magicsk.eu`, verify arrival via IMAP.
7. `mail-tester.com` score ≥ 8/10.
8. Borg job (`systemctl list-timers | grep borg`) runs nightly and includes `/persist/opt/services/stalwart/`.
9. Restart `stalwart-mail`, verify mail still works (catches transient first-run config that didn't persist).

## Out of scope / future work

- Webmail UI (Roundcube / SnappyMail)
- Additional mail domains
- Sieve scripts for advanced filtering
- Push notifications via JMAP
- Migration of existing mail from other providers (manual `imapsync` if needed, separate task)
- Flipping `firewall.enable = true` on magic-pylon (separate task, needs full-service audit)
