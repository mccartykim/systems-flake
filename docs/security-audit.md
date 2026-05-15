# systems-flake Security Audit

**Bead:** sf-h30
**Date:** 2026-05-14
**Scope:** Three-in-one audit covering (1) secrets, (2) network ingress, (3) per-host systemd hardening
**Depends on:** sf-fiz architecture map (`docs/ARCHITECTURE.md`)
**Out of scope:** lifecoach-organism (covered by sf-9ll) — listed but not deep-audited here.

---

## Tally

| Section                          | HIGH | MED | LOW | Total |
| -------------------------------- | ---- | --- | --- | ----- |
| Secrets (agenix / agenix-rekey)  | 0    | 4   | 7   | 11    |
| Network Ingress & Exposure       | 3    | 17  | 4   | 24    |
| Per-Host Systemd Hardening       | 1    | 5   | 3   | 9     |
| **Total**                        | **4**| **26** | **14** | **44** |

The four HIGH-severity findings are the priority items:

1. `hosts/maitred/reverse-proxy.nix` — vacuum dashboard publicly reachable with single-factor SSO
2. `services/default.nix` — reverse-proxy/root domain definitions with `auth = "none"` need explicit audit
3. `hosts/rich-evans/buildbot-master.nix` — Buildbot UI public with only GitHub OAuth
4. `hosts/rich-evans/camera.nix` — `webcam@` socket-activated service has zero hardening

---

## 1. Secrets (agenix / agenix-rekey)

### Background

- Distribution model: `secrets/secrets.nix` defines per-secret `publicKeys` lists. All hosts use their `/etc/ssh/ssh_host_ed25519_key` (`age.identityPaths`) to decrypt.
- A `bootstrap` user-key is in EVERY secret's `publicKeys` (re-encryption convenience). See finding S-11.
- `workingMachines` (every host + bootstrap + oracle + mochi) is used intentionally for `nebula-ca.age`, `restic-password.age`, `restic-b2-env.age` (deduplication needs CA + repo creds everywhere). Not flagged as over-distribution.
- YubiKey-based master identities exist at `secrets/identities/yubikey-1.pub` and `yubikey-2.pub`, but there is no `agenix-rekey` integration wired into the flake (see S-1).

### Findings

- **[MED]** `flake.nix:?` and `secrets/secrets.nix:1` — **S-1: YubiKey master-identity recovery is undocumented.** Two YubiKey public keys exist in `secrets/identities/` but no `agenix-rekey` module is imported, no `masterIdentities` are declared, and no recovery procedure is documented. If both YubiKeys are lost AND the `bootstrap` user key is lost, every secret is unrecoverable without per-host SSH host keys (which themselves rely on physical access). *Fix:* Either wire in `agenix-rekey` with the YubiKeys as masters and add a `docs/recovery.md` describing rotation/loss procedures, or remove the unused YubiKey pubkeys to avoid implying a recovery path that doesn't exist.

- **[MED]** `hosts/rich-evans/email-digest.nix:340-343` — **S-2: `discord-email-digest-token` reuses the life-coach token file.** Line 341 sets `file = ../../secrets/discord-life-coach-token.age;`, meaning the email-digest agent uses the *same Discord bot identity* as the life-coach. There is no separate `discord-email-digest-token.age` declared in `secrets/secrets.nix`. Token reuse couples two service compromises together. *Fix:* Provision a dedicated Discord bot application for email-digest, encrypt the token as `discord-email-digest-token.age`, and declare it in `secrets/secrets.nix` with `publicKeys = [hostKeys.rich-evans bootstrap]`.

- **[MED]** `secrets/nebula-ca.age.new:1` — **S-3: Stale `.age.new` file from incomplete CA rotation.** A 1092-byte `nebula-ca.age.new` sits alongside `nebula-ca.age`. Either rotation completed and the temp file was left behind, or rotation is half-applied. *Fix:* Confirm rotation status; if complete, delete the `.new` file and commit; if incomplete, finish the rotation and document the procedure in `docs/`.

- **[MED]** `hosts/nebula-registry.nix:183-185` — **S-4: Stale mochi host key documented as "almost certainly stale".** The comment says mochi's AVF image was wiped and its SSH key regenerated, but the registry entry was kept "so agenix-rekey can still decrypt to it". Result: nebula-mochi-cert/key secrets are encrypted to a key that no longer exists on the device. *Fix:* Capture mochi's current host key (`ssh-keyscan mochi.nebula`), update `nebula-registry.nix`, then re-run agenix encryption for `nebula-mochi-*.age`. Remove the stale comment.

- **[LOW]** `secrets/secrets.nix:52` — **S-5: `ha-life-coach-token` over-distributed.** Granted to `rich-evans`, `historian`, `marshmallow`, but only rich-evans consumes it (in lifecoach-organism + org-life-coach modules). *Fix:* Drop historian and marshmallow from `publicKeys` and re-encrypt, OR add the planned consumer modules.

- **[LOW]** `secrets/secrets.nix:40-43` — **S-6: `authelia-users.age` declared but never consumed.** The five Authelia secrets reach maitred and historian, but `authelia-users.age` has no corresponding `config.age.secrets.authelia-users` declaration anywhere; the Authelia service reads `/var/lib/authelia-main/users_database.yml` directly. *Fix:* Either wire the agenix secret into the Authelia config (deploy the users DB declaratively) or remove the file and the secrets.nix entry.

- **[LOW]** `secrets/secrets.nix:126` — **S-7: `ollama-cloud-key` over-distributed.** Granted to rich-evans, cheesecake, marshmallow; only rich-evans/sre-agent consumes it. *Fix:* Remove cheesecake and marshmallow unless a planned consumer exists; document the intent if they are intentional pre-positioning.

- **[LOW]** `hosts/historian/configuration.nix:460-464` — **S-8: `jellyfin-api-key` exposed to `media` group via mode `0440`.** Group ownership broadens the reader set beyond what's strictly required if only jellyfin reads it. *Fix:* If both jellyfin and media-classifier need read access (typical), the current mode is correct — add a comment justifying it. If only one service needs read, drop the group and use mode `0400`.

- **[LOW]** `secrets/nebula-arbus-cert.age`, `secrets/nebula-arbus-key.age` — **S-9: Orphan secrets for retired host.** No `arbus` host exists in `hosts/nebula-registry.nix`; these files have no decryption rules in `secrets/secrets.nix`. *Fix:* If arbus is retired, `git rm` the two `.age` files. If arbus is planned, add the registry entry.

- **[LOW]** `secrets/nebula-ca-master.age` — **S-10: Build-time-only secret not tracked in `secrets/secrets.nix`.** Referenced only by `scripts/generate-nebula-certs.nix:86`. *Fix:* Add an explicit comment in `secrets/secrets.nix` documenting that `nebula-ca-master.age` is intentionally NOT a deploy-time secret, OR add it with a single-machine `publicKeys` list for traceability.

- **[LOW]** `hosts/nebula-registry.nix` (bootstrap key) — **S-11: `bootstrap` key origin and recovery undocumented.** Every secret's `publicKeys` includes `bootstrap`. The key's owner, where its private half is stored (cheesecake's user SSH key, per comment), and the loss-recovery procedure are not documented in the repo. If cheesecake's home dir is lost, only host SSH keys can decrypt. *Fix:* Add a section to `docs/ARCHITECTURE.md` (or `docs/recovery.md`) explaining: where the bootstrap private key lives, who has copies, the rotation procedure, and how the YubiKey identities (`secrets/identities/*.pub`) relate.

### Note on test secrets

`secrets/test-nebula-*.age`, `secrets/test-ssh-*.age` are declared in `secrets/test-secrets.nix` (separate from the main rules) and used only by `tests/integration-vm-test.nix`. They are NOT orphans, but `test-secrets.nix` is not referenced by `secrets.nix` itself, so the agenix CLI won't pick them up without an explicit `-r` flag. Not flagged as a finding; documenting for future maintainers.

### No issues identified

- No unencrypted secrets committed to the tree (grep for `ghp_`, `xoxb-`, `sk-`, `Bearer ` finds nothing live).
- No agenix entries with mode looser than `0400` other than the documented `0440 group=media` case (S-8).

---

## 2. Network Ingress & Exposure

### Public ingress inventory (cross-reference for findings below)

| Hostname              | Backend                     | Auth posture                          |
| --------------------- | --------------------------- | ------------------------------------- |
| `kimb.dev`            | Caddy on maitred → blog     | none (public blog)                    |
| `auth.kimb.dev`       | Authelia (port 9091)        | none (public SSO endpoint)            |
| `blog.kimb.dev`       | mist-blog container (8080)  | none (public blog)                    |
| `files.kimb.dev`      | Copyparty (rich-evans:3923) | Authelia 2FA                          |
| `hass.kimb.dev`       | Home Assistant (8123)       | builtin (HA local accounts)           |
| `coach.kimb.dev`      | Lifecoach dashboard (8586)  | Authelia 2FA                          |
| `grafana.kimb.dev`    | Grafana (3000)              | Authelia 1FA                          |
| `prometheus.kimb.dev` | Prometheus (9090)           | Authelia 2FA                          |
| `home.kimb.dev`       | Homepage (maitred:8082)     | Authelia 2FA                          |
| `matrix.kimb.dev`     | Tuwunel (6167)              | builtin Matrix accounts (federated)   |
| `media.kimb.dev`      | Jellyfin (8096)             | builtin Jellyfin accounts             |
| `vacuum.kimb.dev`     | Valetudo (192.168.69.177)   | **Authelia 1FA — see N-1**            |
| `buildbot.kimb.dev`   | Buildbot master             | **GitHub OAuth only — see N-3**       |
| `maitred:4242/udp`    | Nebula lighthouse           | mesh protocol (intentional)           |
| `oracle:4242/udp`     | Nebula lighthouse (cloud)   | mesh protocol (intentional)           |

### Findings

#### Public-ingress / reverse-proxy

- **[HIGH]** `hosts/maitred/reverse-proxy.nix:112` — **N-1: `vacuum.kimb.dev` public with 1FA only.** The vacuum dashboard (Valetudo on `192.168.69.177:80`) is exposed via the public Caddy reverse proxy behind Authelia one-factor. This is a LAN-only IoT device. *Fix:* Either restrict `vacuum.kimb.dev` to LAN/Nebula IPs via the same Caddy `@allowed` block used for grafana, or bump it to Authelia 2FA. Prefer the IP allowlist — there's no reason for it to be public.

- **[HIGH]** `services/default.nix:102-103` — **N-2: Root-domain `kimb.dev` reverse-proxy entry uses `auth = "none"`.** That's correct for the public blog, but the topology DSL has no guard against accidentally pointing the apex domain at a sensitive backend. *Fix:* Add an assertion in `modules/kimb-services.nix` (or wherever the reverse-proxy generator lives) that rejects `publicAccess = true && auth = "none"` for any subdomain matching known-internal patterns (admin, prom, hass, vacuum, …). Whitelist the blog and Authelia explicitly.

- **[HIGH]** `hosts/rich-evans/buildbot-master.nix:22` and `services/default.nix:139` — **N-3: `buildbot.kimb.dev` public, GitHub OAuth only.** Buildbot's web UI is on the public internet with auth backed entirely by a single GitHub OAuth app (client ID 3486605). Buildbot has had auth bypass / RCE history; a public CI server is a high-value target. *Fix:* Restrict `buildbot.kimb.dev` to LAN/Nebula IPs in Caddy (same `@allowed` pattern), or route through Authelia forward_auth on top of GitHub OAuth.

- **[MED]** `services/default.nix:56` — **N-4: `auth.kimb.dev` (Authelia) is `publicAccess=true, auth=none`.** Necessary for SSO but means the Authelia login page is internet-facing. *Fix:* Verify Authelia rate-limiting (`regulation` block) is configured aggressively and consider fail2ban on Caddy access logs for the Authelia endpoint.

- **[MED]** `hosts/maitred/reverse-proxy.nix:45-54` — **N-5: Reverse-proxy generator has no failsafe.** It produces virtual hosts for every `publicAccess = true` service the topology declares. A typo (`auth = "non"` instead of `"none"` would currently produce a broken vhost; `auth = "none"` on the wrong service exposes it). *Fix:* Combine with N-2 — add a sanity-check assertion in the generator.

- **[MED]** `hosts/maitred/authelia.nix:142` — **N-6: SMTP sender uses the owner's personal email.** `kimb@kimb.dev` as the `from` address means MX delivery logs and DKIM/SPF references point to a personal mailbox. *Fix:* Use a `noreply@kimb.dev` or `auth-noreply@kimb.dev` address routed to a transactional mailbox.

- **[MED]** `hosts/maitred/dns-update.nix:27` — **N-7: Cloudflare wildcard DDNS to home IP.** If `*.kimb.dev` is updated to home IP, any future subdomain (typo, accidental commit) is automatically pointed at maitred. *Fix:* Move to explicit per-subdomain inadyn entries; remove the wildcard.

#### Per-host service bindings (services listening on 0.0.0.0 when narrower bind would suffice)

- **[MED]** `hosts/maitred/configuration.nix:380` — **N-8: Unbound DNS on `0.0.0.0`.** *Fix:* Bind to `[127.0.0.1, 192.168.69.1, 10.100.0.50]` only (LAN + Nebula + lo).

- **[MED]** `hosts/maitred/monitoring.nix:311` — **N-9: Grafana `admin_password = "admin"` hardcoded.** Even if Authelia gates the route, anyone who hits Grafana directly via container IP can log in. *Fix:* Provision via agenix (`grafana-admin-password.age`) and reference via `services.grafana.settings.security.admin_password = "$__file{...}"`.

- **[MED]** `hosts/rich-evans/services.nix:80` — **N-10: Home Assistant binds `0.0.0.0:8123`.** Relies entirely on reverse-proxy front + Nebula firewall. *Fix:* Bind to `127.0.0.1` (or `10.100.0.40`) and let Caddy be the only path in.

- **[MED]** `hosts/rich-evans/services.nix:16` — **N-11: Copyparty binds `0.0.0.0`.** *Fix:* Bind to Nebula IP / LAN only; reverse proxy is the only public route.

- **[MED]** `hosts/rich-evans/services.nix:214` — **N-12: Mosquitto on `0.0.0.0:1883` with `allow_anonymous = true`.** Unauthenticated MQTT on a multi-homed host. *Fix:* Bind to `127.0.0.1` if only Home Assistant consumes it, or to Nebula IP if cross-host; add username/password authentication for Valetudo.

- **[MED]** `hosts/rich-evans/services.nix:198` — **N-13: Syncthing GUI on `0.0.0.0:8384`, `openDefaultPorts = true`.** *Fix:* Bind GUI to `127.0.0.1`; restrict sync (22000) and discovery (21027) to Nebula/LAN via firewall rules.

- **[MED]** `hosts/rich-evans/matrix.nix:19` — **N-14: Tuwunel on `0.0.0.0:6167` with federation enabled.** Federation is intentional for Matrix, but the bind should at least be Nebula-only; Caddy proxies to it. *Fix:* Bind to `10.100.0.40` (Nebula) or `127.0.0.1`; Caddy reaches it via the loopback or Nebula IP.

- **[MED]** `hosts/rich-evans/configuration.nix:225` — **N-15: CUPS/IPP on `0.0.0.0:631` with `allowFrom = ["all"]`.** Print server unreachable from outside still costs you a public listener. *Fix:* `listenAddresses = ["192.168.69.x:631"]` and `allowFrom = ["192.168.69.0/24" "10.100.0.0/16"]`.

- **[MED]** `hosts/rich-evans/guacamole.nix:13` — **N-16: Guacamole `host = "0.0.0.0"` with disabled-looking comment.** Verify whether the service is actually enabled. *Fix:* If disabled, set `enable = false;` explicitly; if enabled, bind to Nebula/LAN.

#### Firewall configuration

- **[MED]** `hosts/rich-evans/configuration.nix:291-299` — **N-17: Copyparty ports (3923, 3921, 3945, 3990) opened in `networking.firewall.allowedTCPPorts`.** This bypasses Nebula's per-group filtering. *Fix:* Move to `networking.firewall.interfaces."nebula1".allowedTCPPorts` if Nebula-only is intended; otherwise remove (let reverse proxy be the only public path).

- **[MED]** `hosts/rich-evans/configuration.nix:306-313` — **N-18: Wide port ranges + MQTT 1883 in global allowedTCPPorts/allowedUDPPorts.** Same bypass issue. *Fix:* Use `interfaces.<iface>.allowedTCPPorts` instead of globals.

- **[MED]** `hosts/maitred/configuration.nix:184-195` — **N-19: Ports 53, 80, 443, 631 in global allowed lists with no per-interface scoping.** 80/443 are intended public; 53/631 should be LAN/Nebula only. *Fix:* Move 53 and 631 to `interfaces."br-lan".allowedTCPPorts` / `allowedUDPPorts`.

- **[MED]** `hosts/maitred/configuration.nix:198` — **N-20: `trustedInterfaces = ["enp2s0" "ve-+" "nebula1"]`** — trusting `ve-+` means any container has unrestricted reach into maitred. Containers are not equally trusted (blog-service ≠ reverse-proxy). *Fix:* Drop `ve-+` from trustedInterfaces; explicitly open the ports needed per-container.

- **[LOW]** `hosts/maitred/configuration.nix:52` — **N-21: `kimb.nebula.openToPersonalDevices = true` on maitred.** Grants every desktop/laptop unrestricted port access to the router. Maitred has DNS, reverse proxy, Authelia, monitoring. *Fix:* Replace with explicit `extraInboundRules` enumerating just SSH (22), monitoring scrape (9100/9090/etc.) — let the public-ingress paths remain the only general entry.

- **[MED]** `hosts/rich-evans/services.nix:25` — **N-22: Copyparty `xff-src` trusts entire 192.168.100.0/24 and 10.100.0.0/16.** X-Forwarded-For trust should be limited to the reverse-proxy IP only; anyone else on Nebula can spoof source IP. *Fix:* `xff-src = ["192.168.100.2"];` (just the reverse-proxy container).

- **[MED]** `hosts/historian/configuration.nix:339` — **N-23: Jellyfin `openFirewall = true`.** Jellyfin's library-discovery and DLNA endpoints have historically had unauthenticated info-leak CVEs. *Fix:* Set `openFirewall = false`; reverse proxy reaches it via Nebula explicitly.

- **[LOW]** `hosts/maitred/monitoring.nix:201` — **N-24: `networking.firewall.logRefusedConnections = false`.** Reduces visibility of port-scans on the public IP. *Fix:* Enable; pipe through journal-upload to Loki.

#### No issues identified

- SSH: every profile sets `services.openssh.settings.PasswordAuthentication = false` and `PermitRootLogin = "no"` (or `"prohibit-password"`), authorized keys via `hosts/ssh-keys.nix`. Good posture.
- Tor relay (`hosts/maitred/tor-relay.nix`): correctly configured as a middle relay (not exit). The public-ness of a relay is intentional.
- Nebula lighthouses: both maitred (4242/udp public on home IP) and oracle (4242/udp on `150.136.155.204`) are intentional. Mesh-protocol exposure only.

---

## 3. Per-Host Systemd Hardening

### Custom services audited

**rich-evans** (most service density): `matrix.nix` (mautrix-discord = stock), `buildbot-master.nix`, `email-digest.nix`, `org-crm.nix`, `copyparty` (stock), `kokoro-tts.nix`, `lifecoach-organism` (out of scope, sf-9ll), `lifecoach-freshness-probe`, `sre-agent.nix` (deployed via the module), `webcam@.service`.

**maitred**: `reverse-proxy.nix` (caddy container = stock), `tor-relay.nix` (stock), `authelia.nix` (stock), `systemd-journal-remote`, `monitoring-probes.nix` (ollama-synthetic-probe), `sre-agent` (webhook + Discord + PR worker if enabled).

**historian**: `buildbot-worker.nix` (stock buildbot-nix), `media-classifier` services.

**oracle** (cloud VM, system-manager): nebula, `decrypt-secrets` oneshot, `systemd-resolved`. Minimal attack surface — only nebula listens publicly. No findings; oracle's hardening is acceptable given its narrow role.

**total-eclipse**: `qwen3-tts.nix`.

**cheesecake / mochi / marshmallow / bartleby / donut**: no custom long-running services (desktops/laptops). Out of scope.

### Findings

- **[HIGH]** `hosts/rich-evans/camera.nix:65` — **H-1: `webcam@` socket-activated service has zero hardening.** Runs as `webcam:video` group with no `NoNewPrivileges`, no `ProtectSystem`, no `PrivateTmp`. The `video` group exposes `/dev/video*` and (depending on udev rules) other capture devices. *Fix:*
  ```nix
  serviceConfig = {
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    ReadOnlyPaths = [ "/etc/webcam" ];
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
    LockPersonality = true;
    RestrictRealtime = true;
  };
  ```

- **[MED]** `hosts/rich-evans/kokoro-tts.nix:52` — **H-2: `kokoro-tts` missing kernel/device hardening.** Has `User`/`Group` and `ProtectSystem` but lacks `PrivateDevices`, `ProtectKernelTunables`, `ProtectKernelModules`, `ProtectControlGroups`, `RestrictAddressFamilies`. Service binds to network. *Fix:* Add the missing five directives (see template under H-1).

- **[MED]** `hosts/total-eclipse/qwen3-tts.nix:55` — **H-3: `qwen3-tts` same hardening gap as H-2.** Same fix; preserve CUDA-device access via explicit `DeviceAllow` if `PrivateDevices=true` is too aggressive (CUDA needs `/dev/nvidia*`).

- **[MED]** `hosts/maitred/monitoring.nix:286` — **H-4: `systemd-journal-remote` runs unhardened on maitred.** It accepts journal data from every Nebula host. Even though it runs as the `systemd-journal-remote` user, no `NoNewPrivileges` / `ProtectSystem` / `PrivateTmp` / `RestrictAddressFamilies`. *Fix:*
  ```nix
  systemd.services.systemd-journal-remote.serviceConfig = {
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ReadWritePaths = [ "/var/log/journal/remote" ];
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
  };
  ```

- **[MED]** `modules/sre-agent.nix:171` (sre-agent-webhook), `:217` (sre-agent-discord), `:256` (sre-agent-pr-worker) — **H-5: SRE-agent services read multiple secrets; verify `ReadOnlyPaths` is explicit.** They have `ProtectSystem=strict` and `ProtectHome=true`, but the secrets (`cfg.discordTokenFile`, `cfg.githubTokenFile`, `cfg.ollamaCloudKeyFile`) should be listed under `ReadOnlyPaths` so a future refactor doesn't accidentally make them writable. *Fix:* Add `ReadOnlyPaths = [ cfg.discordTokenFile cfg.githubTokenFile cfg.ollamaCloudKeyFile ];` to each unit's serviceConfig and confirm via `systemd-analyze security sre-agent-webhook` post-deploy.

- **[MED]** `modules/sre-agent.nix:256` — **H-6: sre-agent-pr-worker runs as `cfg.user` natively (not in a container).** Has write access to `cfg.stateDir`. *Fix:* Ensure the `sre-agent` user is declared with `isSystemUser = true; shell = pkgs.shadow;` (or `pkgs.coreutils + /bin/false`), no entry in `users.users.<u>.openssh.authorizedKeys.keys`. Verify with `grep sre-agent /etc/passwd` post-deploy.

- **[LOW]** `hosts/rich-evans/configuration.nix:318` — **H-7: `lifecoach-freshness-probe` (oneshot) lacks sandboxing.** Reads JSON from `/var/lib/lifecoach-organism/.organism/last-run.json` and writes a metric. Low risk because oneshot + minimal scope. *Fix:* Add `ProtectSystem=strict; ProtectHome=true; PrivateTmp=true;` for consistency with other probes.

- **[LOW]** `hosts/maitred/monitoring-probes.nix:17` — **H-8: `ollama-synthetic-probe` runs as root.** Shell script that curl's an endpoint. Doesn't need root. *Fix:* Add a `monitoring` system user (or reuse an existing prometheus-* user) and set `User = "monitoring"; NoNewPrivileges = true; ProtectSystem = "strict";`.

- **[LOW]** `modules/observability.nix:38` — **H-9: `systemd-journal-upload` runs as root with no hardening.** Pushes journal data outbound. *Fix:* Same template as H-4, with a dedicated unprivileged user or by setting `User = "systemd-journal-upload"` if the journal client supports drop-priv.

### Out-of-scope but listed for completeness

| Service                          | Status / Owner            |
| -------------------------------- | ------------------------- |
| `lifecoach-organism`             | sf-9ll (already audited)  |
| `lifecoach-organism` (fix bead)  | sf-s0e                    |
| `mautrix-discord`                | stock nixpkgs             |
| `mist-blog` container            | stock container module    |
| Caddy (reverse-proxy container)  | stock (upstream hardened) |
| Authelia                         | stock                     |
| Tor (relay)                      | stock                     |
| buildbot-master / buildbot-worker| stock buildbot-nix module |

---

## Appendix: Methodology

1. Enumerated secrets from `secrets/secrets.nix` and grep'd consumers via `config.age.secrets.<name>`.
2. Enumerated public ingress by reading the `kimb-services` topology and `hosts/maitred/reverse-proxy.nix`.
3. Enumerated firewall posture per host via `grep -rn 'allowedTCPPorts\|allowedUDPPorts\|trustedInterfaces' hosts/`.
4. Enumerated custom systemd units via `grep -rln 'systemd.services\.' hosts/ modules/ services/` and audited each against the standard hardening directive list.

Findings are line-accurate as of commit on branch `polecat/slit/sf-h30@mp6a9ioh` (2026-05-14). Line numbers may drift; the file:line cross-reference is intended as a starting point, not a permanent locator.
