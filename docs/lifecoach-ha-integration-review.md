# Lifecoach-organism HA integration review (rich-evans)

**Scope.** Audit the systems-flake side of the `lifecoach-organism` deployment on
rich-evans: how the agent is wired into NixOS, how Home Assistant triggers it,
what isolation it gets. Code-level audit of the upstream `lifecoach_organism`
package is out of scope; this review covers the module's NixOS surface and the
host-side glue.

**Files audited.** `hosts/rich-evans/{lifecoach-organism,org-life-coach,life-coach,services,configuration}.nix`,
`tests/kimb-services-integration-test.nix`, `secrets/secrets.nix`,
`services/default.nix`, the upstream module at
`/home/kimb/shared-projects/lifecoach_organism/nixos/module.nix`, and the still-
imported `/home/kimb/shared-projects/org_life_coach/flake.nix` (signal scripts).

**Severity legend.** `HIGH` = exploitable in current config or data-loss class;
`MEDIUM` = degraded posture or latent footgun; `LOW` = hygiene / over-scoping.

---

## 1. Systemd unit hardening

### 1.1 No systemd sandboxing on any lifecoach unit — `HIGH`

`lifecoach_organism/nixos/module.nix:518-702` defines seven systemd services
(`lifecoach-heartbeat`, `lifecoach-scheduler`, `lifecoach-button-monitor`,
`lifecoach-discord-bot`, `lifecoach-dashboard`, `lifecoach-watchdog`,
`lifecoach-ollama-warmup`, `lifecoach-creds-canary`). Every one sets only
`User`/`Group`/`WorkingDirectory`/`ExecStart`/`Type`. None set
`ProtectSystem`, `ProtectHome`, `NoNewPrivileges`, `PrivateTmp`,
`ReadWritePaths`, `RestrictAddressFamilies`, `RestrictNamespaces`,
`CapabilityBoundingSet`, `LockPersonality`, `MemoryDenyWriteExecute`, or
`SystemCallFilter`.

These services run `claude -p`, whose `Bash` tool spawns arbitrary shell.
"Arbitrary shell as `life-coach`" currently means full read/write to:
`/var/lib/life-coach-agent/` (org-agent state + state.db),
`/var/lib/lifecoach-organism/` (org file, snapshots, log),
`/var/lib/vacuum-organism/dispatch.org` (via shared group), the HA / Discord
tokens at `/run/agenix/`, and anything else world-readable on the box. The
`life-coach` user can also touch HA via 127.0.0.1:8123, the local emacs
daemon socket, the local Ollama proxy, and Nebula.

**Fix.** Add a hardening overlay in `hosts/rich-evans/lifecoach-organism.nix`
applying the following to every `lifecoach-*` service:

```nix
serviceConfig = {
  NoNewPrivileges = true;
  ProtectSystem = "strict";
  ProtectHome = true;
  PrivateTmp = true;
  PrivateDevices = true;
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectControlGroups = true;
  RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
  RestrictNamespaces = true;
  LockPersonality = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  ReadWritePaths = [
    "/var/lib/lifecoach-organism"
    "/var/lib/life-coach-agent"        # emacs daemon socket + org files
    "/var/lib/vacuum-organism"         # dispatch.org via shared group
    "/var/lib/prometheus-node-exporter-textfiles"  # freshness probe
  ];
};
```

Test interactively first — the `Bash` tool may need `/tmp` writable
(`PrivateTmp=true` is fine, it gives a per-unit private `/tmp`) and the
`claude` CLI may want `$HOME` writable for credential refresh
(`/var/lib/life-coach-agent` is already `$HOME` per
`lifecoach_organism/nixos/module.nix:684-689`).

This should land as a separate PR with each service tested individually; one
wrong `ReadWritePaths` and the agent silently breaks until the next
heartbeat watchdog.

### 1.2 Button-monitor crash-loop hammers HA — `MEDIUM`

`lifecoach_organism/nixos/module.nix:560-585` sets:

```nix
Restart = "always";
RestartSec = "10s";
```

with no `StartLimitBurst` / `StartLimitIntervalSec`. If HA is down or the
token file is unreadable, `button-monitor` exits, restarts in 10s, exits,
restarts in 10s, forever. The poll itself isn't free — it's a sequence of
HA REST `GET /api/states/...` calls plus disk reads of the agenix token.

**Fix (in this repo, via `systemd.services.lifecoach-button-monitor.serviceConfig`):**

```nix
StartLimitBurst = 5;
StartLimitIntervalSec = 300;
StartLimitAction = "none";   # already the default; explicit beats implicit
```

After 5 crashes in 5 minutes systemd marks the unit failed and lets the
watchdog notice. Same recommendation for `lifecoach-discord-bot` and
`lifecoach-dashboard` (currently `Restart = "on-failure"` with no burst cap).

### 1.3 Concurrent heartbeat + scheduler can race on `agent.org` — `MEDIUM`

`lifecoach_organism/nixos/module.nix:452-474, 522-551`: both
`lifecoach-heartbeat` and `lifecoach-scheduler` are `Type=oneshot`, both
invoke `lifecoach-invoke`/`lifecoach-check-schedule` against the same
`agent.org`. systemd serializes within a unit but not across units. If the
scheduler fires at minute boundaries and a heartbeat happens to fire on the
same minute, two `claude -p` invocations rewrite the same org file
concurrently.

**Fix.** Confirm whether `bin/lifecoach-invoke` and `bin/lifecoach-check-schedule`
take an internal `flock` on `$LIFECOACH_ORG`. If not, wrap both `ExecStart`
lines in `${pkgs.util-linux}/bin/flock -n /var/lib/lifecoach-organism/.cycle.lock`
via an override in `hosts/rich-evans/lifecoach-organism.nix`. File this as a
follow-up: it's hard to hit but corruption is silent when it does happen.

### 1.4 `stop-old-org-life-coach` activation script is one-shot — `LOW`

`hosts/rich-evans/lifecoach-organism.nix:149-157`. The activation stops the
old daemon imperatively on switch. If a future change re-enables it (e.g. a
downstream module reasserts `wantedBy = ["multi-user.target"]`), the
activation won't kill it until the next `nixos-rebuild switch`. Not exploitable;
worth a comment pointing at the cutover plan so future readers know this is
load-bearing.

### 1.5 `freshness-probe` is unhardened — `LOW`

`hosts/rich-evans/configuration.nix:318-343`. Same lack of `ProtectSystem`
etc. as 1.1, but the script only reads one JSON file and writes one .prom
file — narrow blast radius. Apply the hardening overlay anyway when 1.1
lands.

---

## 2. Webhook / button auth and delivery

### 2.1 Dashboard `/api/...` endpoints have no auth on direct port 8586 — `HIGH`

The dashboard FastAPI app (`lifecoach_organism/dashboard/api.py`) exposes
state-mutating endpoints with **no in-app authentication**:

- `POST /trigger`            (api.py:484) — fire an agent cycle
- `POST /state`              (api.py:322)
- `POST /reschedule`         (api.py:336)
- `POST /deadline`           (api.py:350)
- `POST /check` / `/uncheck` (api.py:364, 373)
- `POST /log`                (api.py:386)
- `POST /insert`             (api.py:400)
- `POST /reconcile`          (api.py:410)
- `POST /property`           (api.py:439)
- `DELETE /property`         (api.py:457)

It listens on `0.0.0.0:8586` (`hosts/rich-evans/lifecoach-organism.nix:70-74`,
`dashboard.host` defaults to `0.0.0.0` per module.nix:415,
`openFirewall = true`). The Nebula firewall opens 8586 from
`host = "any"` (`hosts/rich-evans/configuration.nix:144-148`).

The reverse-proxy route at `coach.kimb.dev` IS gated by Authelia
(`services/default.nix:42, auth = "authelia"`). The direct paths are not:

- **Nebula:** any host in the mesh (10.100.0.0/16) can `curl
  http://rich-evans.nebula:8586/trigger` and fire a cycle, rewrite org
  state, etc.
- **LAN:** any device on 192.168.69.0/24 can do the same.
- **Localhost:** anything running as any user on rich-evans can do the
  same — note this means `nobody` in a half-broken container.

**Fix (preferred — bind to loopback).**

```nix
# hosts/rich-evans/lifecoach-organism.nix
services.lifecoach-organism.dashboard = {
  host = "127.0.0.1";
  openFirewall = false;
};
```

Then drop port 8586 from `kimb.nebula.extraInboundRules`
(configuration.nix:144-148). The reverse proxy on maitred reaches the
dashboard over Nebula via `proxy_pass http://rich-evans:8586`, so a maitred-only
firewall rule is the minimum.

**Fix (alternative — narrow firewall).** Keep direct access for personal
devices only:

```nix
{ port = 8586; proto = "tcp"; groups = ["desktops" "laptops"]; }
```

…and add an `extraInboundRules` entry for maitred. This still leaves
LAN bypass; prefer the loopback fix.

### 2.2 Discord bot allows ALL users — `HIGH`

`hosts/rich-evans/lifecoach-organism.nix:60` comments
`# discordAllowedUsers left empty = allow all`, and
`lifecoach_organism/nixos/module.nix:311-318` confirms `""` means "allow
all". Anyone who shares a Discord guild with the bot can run `/ask` and
`/task`, which fire `lifecoach-invoke` (cost to Kim) and inject text into
the LLM prompt (prompt-injection surface). If the bot is in any public
server, this is open-door.

**Fix.** Populate the allowlist:

```nix
discordAllowedUsers = "111111111111111111,222222222222222222";  # Kim's IDs
```

Confirm `bin/discord-bot` actually enforces the env var (the option
description says it does, but the upstream impl should be spot-checked).
File a follow-up bead if upstream doesn't enforce it.

### 2.3 HA `shell_command` button signals write to a dead queue — `MEDIUM`

`hosts/rich-evans/services.nix:93-109` wires HA `shell_command.signal_*`
entries that all call into `/etc/life-coach-agent/signal_button_press.sh`,
`signal_user_input.sh`, and `signal_location_change.sh`. Those scripts are
shipped by the OLD `org-life-coach` module
(`/home/kimb/shared-projects/org_life_coach/flake.nix:393-431`) and all do:

```bash
sqlite3 /var/lib/life-coach-agent/state.db \
  "INSERT INTO interrupt_events ..."
```

That `state.db` row was consumed by `org-life-coach.service` — which
`hosts/rich-evans/lifecoach-organism.nix:147` disables via
`wantedBy = lib.mkForce []` plus the imperative stop at line 149-157.
The new `lifecoach-button-monitor` polls HA REST API directly
(`lifecoach_organism/nixos/module.nix:560-585`) and never reads
`state.db`.

**Impact today.** Every HA button press silently writes to a queue no
one drains. `state.db` grows unbounded (slowly — a few rows/day) and the
HA-side automations succeed silently while the agent never reacts. The
location-change automation (services.nix:111-153) and the
`life_coach_submit` input button (services.nix:156-165) are also dead
paths.

**Fix.** Either:

(a) **Delete the dead wiring** — remove the `shell_command` block at
services.nix:93-109, the location-tracking automation at services.nix:111-153,
the submit-input automation at services.nix:154-166, and the
`input_text.life_coach_input` / `input_button.life_coach_submit` entries
at services.nix:172-187 if they're no longer the input surface.

(b) **Repurpose them** to call a new lifecoach signal — e.g. emit
`POST http://127.0.0.1:8586/trigger?source=button&id=$BUTTON` once the
dashboard is loopback-bound. This is the clean replacement for the
button-monitor poll on the buttons HA already owns.

Option (a) is the smaller change; option (b) is the right long-term move
because it eliminates the 1-2s polling latency in button-monitor.

### 2.4 SQL injection in dead signal scripts — `LOW` (latent)

`org_life_coach/flake.nix:403-404, 413-414, 428-429`: every signal script
interpolates `$1` into a literal `INSERT` statement:

```bash
sqlite3 .../state.db "INSERT INTO interrupt_events (...) VALUES ('button_press', '{\"button\": \"$BUTTON_ID\"}');"
```

Today the only callers are HA's hard-coded `shell_command` stanzas
passing fixed strings (`desk_button`, `desk_task_1`, …). If a future
change ever wires user-controlled input here (a templated automation,
say), it's an SQL injection straight into the daemon's state. Severity is
LOW because the obvious fix is 2.3(a) — delete the dead path.

**Fix if keeping.** Use `sqlite3 -cmd ".parameter set ..."` or pipe a
HEREDOC with `?`-bind parameters, not string interpolation.

### 2.5 Button-monitor → HA auth — OK

`/run/agenix/ha-life-coach-token` is read lazily by `lib/ha.py` (per the
comment at `lifecoach_organism/nixos/module.nix:566-572`) over loopback
HTTP. No mTLS, no replay protection — fine for 127.0.0.1.

### 2.6 No HA trigger-string sanitization — out of scope

The agent treats button names, Discord prompt text, and reschedule
strings as untrusted **for the LLM**. That's a prompt-engineering
concern (lib-level), not a systems-flake concern. Note for completeness:
nothing at the NixOS layer can defend against LLM prompt injection;
defenses live in the agent.

---

## 3. Secrets

### 3.1 `ha-life-coach-token.age` over-distributed — `LOW`

`secrets/secrets.nix:52`:

```nix
"ha-life-coach-token.age".publicKeys =
  [hostKeys.rich-evans hostKeys.historian hostKeys.marshmallow bootstrap];
```

Only rich-evans declares `age.secrets.ha-life-coach-token` (life-coach.nix:14-18)
and `age.secrets.ha-vacuum-token` (life-coach.nix:26-30). historian and
marshmallow can decrypt the same `.age` blob with their host keys but
never do. If either host is compromised, the HA long-lived token leaks.

**Fix.** Narrow to:

```nix
"ha-life-coach-token.age".publicKeys = [hostKeys.rich-evans bootstrap];
```

…unless there's a planned cross-host use (which would also need a
corresponding `age.secrets.*` declaration on the consuming host).

### 3.2 Unused `gemini-life-coach-key` — `LOW`

`hosts/rich-evans/life-coach.nix:46-51` and `secrets/secrets.nix:58`
declare `age.secrets.gemini-life-coach-key` but the comment in
`hosts/rich-evans/org-life-coach.nix:50-51` notes Gemini is unused (vision
goes via Claude multimodal). Dead encrypted secret on disk + dead
publicKeys entry. Delete both.

### 3.3 Token ownership and modes — OK

`hosts/rich-evans/life-coach.nix:13-51` consistently sets `owner = "life-coach"`
and `mode = "0400"` for every lifecoach secret. The vacuum side declares a
second decryption (`age.secrets.ha-vacuum-token`, life-coach.nix:26-30)
with the same encrypted source but owned by `vacuum-organism` user, mode
0400 — exactly the right pattern. The Discord and Matrix tokens are
group-scoped to `life-coach` only.

### 3.4 `DISCORD_BOT_TOKEN_FILE` exported to every cycle service — note, not flag

`lifecoach_organism/nixos/module.nix:127-130` adds
`DISCORD_BOT_TOKEN_FILE` to `cycleEnv` so cycle services can `discord-reply`
without a separate token path. Everything in `cycleEnv` runs as `life-coach`
already, so the trust boundary doesn't widen — but it means any shell
spawned by the agent via the `Bash` tool can `cat $DISCORD_BOT_TOKEN_FILE`.
Acceptable; mention in 1.1's hardening doc so reviewers know it.

### 3.5 No secrets logged — verified by grep

`syncAgentLine` (module.nix:43-87), button-monitor, discord-bot, and the
freshness probe (configuration.nix:325-342) don't echo token contents.
Spot-check, not exhaustive.

---

## 4. Failure semantics

### 4.1 `claude -p` failure → next heartbeat — OK

Cycle services are `Type=oneshot`. A failed `claude -p` exits non-zero;
systemd records `result=exit-code`; the heartbeat timer (30 min) fires
the next cycle. `lifecoach-watchdog` reads `health.json` every 5 min
(module.nix:479-487, 641-658) and fans out TTS + Discord DM when
`status=broken`. Reasonable closed loop.

### 4.2 Corrupt `agent.org` → no auto-recovery — `MEDIUM`

`lifecoach_organism/nixos/module.nix:65-71`: if the live org file has no
`* Today` heading, `syncAgentLine` logs and skips, preserving the
corrupt file. The cycle service still runs and `claude -p` likely fails.
The watchdog sees `broken` and pages. There's no auto-restore from the
last `.organism/` snapshot.

**Fix (follow-up).** Add a stage to `syncAgentLine` that falls back to
the most recent `${stateDir}/.organism/agent.org.*.bak` if
`LIVE_TAIL` is empty. Upstream change in `lifecoach_organism`; file a
bead against that repo.

### 4.3 HA unreachable → button-monitor restart-loop — see 1.2

### 4.4 `flock` not used cross-unit — see 1.3

### 4.5 No alert on `lifecoach-button-monitor` unit failure — `LOW`

The watchdog alerts on `health.json status=broken` (which is set by
cycles, not by sidecar state). If `button-monitor` enters
`auto-restart` jail (after 1.2 lands) or otherwise stays `failed`, no
metric exports that fact.

**Fix.** Add a Prometheus alert on
`node_systemd_unit_state{name="lifecoach-button-monitor.service",state="failed"}`.
Lives in maitred's `prometheus.rules` alongside `ResticBackupStale`.

### 4.6 Activation-script cutover is point-in-time — `LOW` (see 1.4)

---

## 5. Test coverage

### 5.1 No HA → lifecoach end-to-end test — `HIGH`

`tests/kimb-services-integration-test.nix` (155 lines) exercises only the
`kimb-services` module abstraction: it brings up a router + a server,
asserts nginx/prometheus listen on the computed ports, and checks
cross-machine ping. It does NOT:

- import `lifecoach-organism.nixosModules.default`
- run HA with the lifecoach automations
- press an `input_button`
- verify `button-monitor` picked up the press
- invoke a cycle

The entire user-facing path (HA button → cycle → org write → TTS) is
uncovered.

**Fix.** Add `tests/lifecoach-button-monitor-test.nix`:

```nix
pkgs.testers.nixosTest {
  name = "lifecoach-button-monitor";
  nodes.host = { ... }: {
    imports = [ lifecoach-organism.nixosModules.default ];
    services.home-assistant.enable = true;
    services.home-assistant.config.input_button.test_button = {};
    services.lifecoach-organism = {
      enable = true;
      enableButtonMonitor = true;
      haUrl = "http://127.0.0.1:8123";
      haTokenFile = "/etc/ha-token";  # plain text in test
    };
    environment.etc."ha-token".text = "fake-token";
    # Mock /etc/ollama-stub or override ANTHROPIC_BASE_URL to an in-VM stub
  };
  testScript = ''
    host.wait_for_unit("home-assistant.service")
    host.wait_for_unit("lifecoach-button-monitor.service")
    host.succeed("curl -X POST http://127.0.0.1:8123/api/services/input_button/press ...")
    host.wait_until_succeeds("journalctl -u lifecoach-button-monitor | grep test_button")
    host.wait_until_succeeds("test -f /var/lib/lifecoach-organism/.organism/last-run.json")
  '';
}
```

Non-trivial — needs a stub Ollama endpoint and an org-agent emacs stub.
File as follow-up; don't block the existing migration on it.

### 5.2 Eval check exists — OK

`nix flake check` will catch type errors in the lifecoach options surface
via the existing `eval-historian`-style eval checks. That's the only
automated guard right now.

---

## Summary

| # | Finding | Severity |
|---|---------|----------|
| 1.1 | No systemd sandboxing on any lifecoach unit | HIGH |
| 1.2 | button-monitor crash-loops with no rate limit | MEDIUM |
| 1.3 | heartbeat + scheduler can race on agent.org | MEDIUM |
| 1.4 | Cutover activation is one-shot | LOW |
| 1.5 | Freshness-probe unhardened | LOW |
| 2.1 | Dashboard /api/* unauthenticated on port 8586 (Nebula + LAN) | HIGH |
| 2.2 | Discord bot allowlist empty = allow all | HIGH |
| 2.3 | HA shell_command signal writes to a dead queue | MEDIUM |
| 2.4 | SQL injection in dead signal scripts (latent) | LOW |
| 3.1 | ha-life-coach-token decryptable on historian + marshmallow | LOW |
| 3.2 | gemini-life-coach-key declared but unused | LOW |
| 4.2 | Corrupt agent.org has no auto-recovery | MEDIUM |
| 4.5 | No alert on button-monitor unit failure | LOW |
| 5.1 | No HA→lifecoach end-to-end test | HIGH |

Top-of-list to fix first, in order:

1. **2.2 Discord allowlist** — one-line change in
   `hosts/rich-evans/lifecoach-organism.nix`, immediate exposure reduction.
2. **2.1 Bind dashboard to loopback** + drop port 8586 from Nebula firewall.
   ~4 lines, no behavior change for users hitting `coach.kimb.dev`.
3. **2.3 Delete dead HA shell_command wiring** in `hosts/rich-evans/services.nix`.
   Removes a confusing silent-failure path.
4. **1.1 Systemd hardening overlay** — bigger change, needs per-service
   testing, but the highest blast-radius reduction once it lands.
5. **3.1 Narrow ha-life-coach-token publicKeys** + **3.2 delete gemini secret**.
6. Everything else as follow-up beads.

No code/nix changes made in this review per the bead's acceptance criteria.
