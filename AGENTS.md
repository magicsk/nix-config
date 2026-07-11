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
- Persistent service config/data directories should be owned by `homelab.user`/`homelab.group`, or otherwise be readable and writable by the intended operator or service-specific user; avoid root-only persistent directories unless secrets or upstream ownership requirements demand it.
- `homepage.*` options feed the generated homepage dashboard. Add them only for services with a web UI.
- For Homepage selfh.st icons (`sh-*`), use the default PNG form or an explicit `.png`/`.webp` when the selfh.st index does not provide SVG; forcing `.svg` breaks icons such as Bugsink.
- Services without a web UI should not define `homepage.*` and should not define a `url` solely for homepage generation.
- Home Assistant runs with `--network=host` so it reaches bridge-mode containers on `127.0.0.1:<exposed-port>`.
- On `magic-pylon`, Zigbee2MQTT uses the CH340 serial adapter `/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0` (`/dev/ttyUSB0`) with `rtscts = false`; OTBR/Thread owns `/dev/ttyACM0`, so do not swap these while debugging serial conflicts.
- Bridge-mode containers should reach each other by container name on the Podman DNS-enabled network.
- Caddy uses a wildcard ACME certificate for `*.${config.homelab.baseDomain}` through Cloudflare DNS. New virtual hosts normally only need `useACMEHost = homelab.baseDomain`.
- Cloudflare-proxied service records that target `pylon.magicsk.eu` depend on `magic-pylon` owning the static IPv6 `2a01:c846:3901:9301::a` on `br0` with a default route via `fe80::921b:eff:febf:7819%br0`; if those records return `523` after reboot, check the host IPv6 address and route before changing DNS.
- Some services use `configDir`, while most use `dataDir`; follow the upstream container or service mount semantics rather than forcing one convention.
- When adding a new service module, also enable it in `machines/nixos/magic-pylon/homelab/default.nix` under `homelab.services`.
- Public Git-deployed websites are managed through `homelab.services.websites`; restarting a `website-*` service pulls the repo and rebuilds before serving or starting it.
- `website-*` services run dependency install/build work during start; keep their systemd start timeout long enough for production builds after package/runtime updates.
- `homelab.services.codex-wrapper` uses prebuilt Nix `nodejs`/`codex` binaries and prepares a pinned CodexBridge checkout under the persistent service `dataDir`; avoid moving its source checkout or npm cache into the Nix store because that makes rebuilds unnecessarily long.
- `homelab.services.codex-wrapper` should keep live `web_search` and `personality = "pragmatic"` in its managed Codex config; it relies on the central `homelab.user` WireGuard bypass in `magic-pylon/network/wireguard.nix` for home-WAN web/OpenAI traffic.
- Headscale still runs on the Oracle VPS. `homelab.services.headscale` only adds the `hs.magicsk.eu` Caddy reverse proxy on `magic-pylon`, with upstream `http://172.16.16.1:8080` over WireGuard; the VPS headscale service listens on `0.0.0.0:8080` and `/etc/iptables/rules.v4` allows TCP/8080 from `wg0`.
- Oracle VPS public-ingress DNAT rules must be scoped to `-i ens3`. Unscoped port 80/443 DNAT catches `wg0` egress from `magic-pylon` and loops arbitrary outbound HTTPS back to Caddy, causing TLS internal errors.
- If Homepage reports many local services flapping but Caddy-local `GET` checks pass, check whether service FQDNs resolve to the Oracle ingress `132.226.217.72`; non-`homelab.user` service UIDs route that address through `wg0`, so host-local probes should avoid the public ingress path.
- Cloudflare-proxied web records should target `pylon.magicsk.eu` or the direct pylon IPv6 origin, not the apex `magicsk.eu` record if it still points at the Oracle VPS IPv4; `reciper.magicsk.eu` returned intermittent Cloudflare `522` until its proxied CNAME was moved from `magicsk.eu` to `pylon.magicsk.eu`.
- `magic-pylon` is reachable with `ssh magic_sk@magic-pylon.local` for debugging, container status, and logs.
- On `magic-pylon`, root traffic still uses the WireGuard route; GitHub/GHCR can fail there with TLS internal errors. For rebuilds that need GitHub fetches, build as `magic_sk`, then switch the exact built system path with sudo.
- Do not leave stateful-service upgrades only test-activated. If a `nixos-rebuild test` or direct `switch-to-configuration test` starts newer packages such as Nextcloud and upgrades persistent data, run the matching `switch-to-configuration switch` before reboot or the host can boot an older generation that refuses the newer data.
- On 26.05, bind mounts declared in `fileSystems` need explicit `fsType = "none"`.
- `services.stalwart-mail` was renamed to `services.stalwart` on 26.05; for pre-26.05 Stalwart data, keep `stateVersion = "25.11"` and the legacy user/group when needed.
- On 26.05, `pkgs.nodejs_20` is insecure/EOL; `homelab.services.codex-wrapper` should use the supported default `pkgs.nodejs`.

## magic-pylon WireGuard Routing

- `machines/nixos/magic-pylon/network/wireguard.nix` configures `wg0` with `allowedIPs = [ "0.0.0.0/0" ]`, so IPv4 traffic is treated as a selective full tunnel.
- Do not remove existing WireGuard bypass rules without checking which service depends on them.
- Redlib runs as the upstream Podman container `quay.io/redlib/redlib:latest` (not the nixpkgs build, which lags the `wreq` TLS-fingerprint fix and gets 403/401-blocked by Reddit's anti-bot edge). It bypasses the VPN on subnet `172.30.16.0/24` because Reddit blocks the VPS public IP. The previous `uidrange 994-994` bypass and the native `services.redlib`/uid-994 user were removed in this migration.
- Home Assistant/HACS must bypass the VPN by the `homelab.user` UID because GitHub rejects TLS handshakes from the VPS path.
- Flaresolverr must bypass the VPN on subnet `172.30.12.0/24` because Cloudflare also blocks the VPS public IP.
- Paperless uses bypass subnet `172.30.13.0/24` for large outbound fetches that fail through the WireGuard MTU path.
- Paperless-ngx 2.20.15 defaults its webserver bind to `::`; keep `PAPERLESS_BIND_ADDR = "0.0.0.0"` because this host's Podman IPv4 port forwarding cannot reach the IPv6-only listener.
- changedetection.io uses bypass subnet `172.30.14.0/24` so monitored website checks leave through the home connection, not the VPS tunnel.
- changedetection.io Chrome/WebDriver fetching expects the internal hostname `browser-chrome`; keep the Selenium companion container on the same `changedetection-io` Podman network and do not expose its port publicly.
- html2rss-web uses bypass subnet `172.30.15.0/24` and an internal Browserless Chromium companion; it cannot directly reuse changedetection.io's Selenium `browser-chrome` because html2rss expects the Browserless websocket/API protocol.
- Tailscale needs both the `100.64.0.0/10` and `100.100.100.100/32` routes through `tailscale0`, plus the `fwmark 0x80000/0xff0000 table main priority 95` bypass for underlay encapsulated packets.
- When adding a service blocked from the VPS public IP, or a service that runs its own tunnel or overlay, add a WireGuard bypass in `postUp` and `preDown` by UID, source subnet, or fwmark with priority lower than the generated WireGuard rules. Current service bypasses use priority `86`, before the generated suppress/full-tunnel rules.
- Podman containers that perform large outbound transfers or arbitrary public web fetches should use a bypassed network. The current bypassed `/24` subnets are `172.30.12.0/24` for flaresolverr, `172.30.13.0/24` for paperless, `172.30.14.0/24` for changedetection.io, `172.30.15.0/24` for html2rss-web, and `172.30.16.0/24` for redlib; choose the next free `172.30.x.0/24` (next is `172.30.17.0/24`) for another bypassed network.
- Adding a *new* bypassed Podman network through `nixos-rebuild switch` (no reboot) can leave `aardvark-dns` not listening on the new gateway `172.30.<n>.1:53`, so containers on it fail DNS with `Could not resolve host` (e.g. redlib logs `Failed to create OAuth client before timeout`). Fix once with `sudo podman network reload --all` (rebinds every gateway); a reboot also fixes it because all networks are created before their containers start. Verify which gateways are bound with `sudo ss -ulnp | grep ':53 '`.
