# Repository Agent Instructions

These instructions apply across this repository.

## Command Policy

- Do not prefix commands with `rtk`. Run commands directly.
- This repo is usually edited through `/Volumes/config/nixos`, which may be an SMB mount. If local Git operations on the mount are unreliable, SSH to `magic_sk@fd7a:115c:a1e0::1` or `magic_sk@magic-pylon.local` and use the host checkout at `/etc/nixos` before changing Git history.

## Maintaining These Instructions

- When you discover durable repo-specific information that was not obvious or easily findable from the checked-in files, add it to this `AGENTS.md` before finishing the task.
- Keep new notes concise, operational, and scoped to future agents working in this repo.

## Homelab Service Conventions

- `magic-pylon` enables `programs.nix-ld` so generic dynamically linked Linux binaries can run; Warp's SSH extension remote server depends on this.
- Every service with persistent data must declare `environment.persistence."/"`; otherwise its data can be lost after rebuilds.
- `homepage.*` options feed the generated homepage dashboard. Add them only for services with a web UI.
- For Homepage selfh.st icons (`sh-*`), use the default PNG form or an explicit `.png`/`.webp` when the selfh.st index does not provide SVG; forcing `.svg` breaks icons such as Bugsink.
- Services without a web UI should not define `homepage.*` and should not define a `url` solely for homepage generation.
- Home Assistant runs with `--network=host` so it reaches bridge-mode containers on `127.0.0.1:<exposed-port>`.
- Bridge-mode containers should reach each other by container name on the Podman DNS-enabled network.
- Caddy uses a wildcard ACME certificate for `*.${config.homelab.baseDomain}` through Cloudflare DNS. New virtual hosts normally only need `useACMEHost = homelab.baseDomain`.
- Some services use `configDir`, while most use `dataDir`; follow the upstream container or service mount semantics rather than forcing one convention.
- When adding a new service module, also enable it in `machines/nixos/magic-pylon/homelab/default.nix` under `homelab.services`.
- Public Git-deployed websites are managed through `homelab.services.websites`; restarting a `website-*` service pulls the repo and rebuilds before serving or starting it.
- Headscale still runs on the Oracle VPS. `homelab.services.headscale` only adds the `hs.magicsk.eu` Caddy reverse proxy on `magic-pylon`, with upstream `http://172.16.16.1:8080` over WireGuard; the VPS headscale service listens on `0.0.0.0:8080` and `/etc/iptables/rules.v4` allows TCP/8080 from `wg0`.
- `magic-pylon` is reachable with `ssh magic_sk@magic-pylon.local` for debugging, container status, and logs.
- On `magic-pylon`, root traffic still uses the WireGuard route; GitHub/GHCR can fail there with TLS internal errors. For rebuilds that need GitHub fetches, build as `magic_sk`, then switch the exact built system path with sudo.

## magic-pylon WireGuard Routing

- `machines/nixos/magic-pylon/network/wireguard.nix` configures `wg0` with `allowedIPs = [ "0.0.0.0/0" ]`, so IPv4 traffic is treated as a selective full tunnel.
- Do not remove existing WireGuard bypass rules without checking which service depends on them.
- Redlib must bypass the VPN by UID because Reddit blocks the VPS public IP. The existing rule is `uidrange 994-994 table main`.
- Home Assistant/HACS must bypass the VPN by the `homelab.user` UID because GitHub rejects TLS handshakes from the VPS path.
- Flaresolverr must bypass the VPN on subnet `172.30.12.0/24` because Cloudflare also blocks the VPS public IP.
- Paperless uses bypass subnet `172.30.13.0/24` for large outbound fetches that fail through the WireGuard MTU path.
- Tailscale needs both the `100.64.0.0/10` and `100.100.100.100/32` routes through `tailscale0`, plus the `fwmark 0x80000/0xff0000 table main priority 95` bypass for underlay encapsulated packets.
- When adding a service blocked from the VPS public IP, or a service that runs its own tunnel or overlay, add a WireGuard bypass in `postUp` and `preDown` by UID, source subnet, or fwmark with priority lower than the generated WireGuard rules. Current service bypasses use priority `86`, before the generated suppress/full-tunnel rules.
- Podman containers that perform large outbound transfers should use a bypassed network. The current bypassed `/24` subnets are `172.30.12.0/24` for flaresolverr and `172.30.13.0/24` for paperless; choose the next free `172.30.x.0/24` for another bypassed network.
