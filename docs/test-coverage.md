# systems-flake Test Coverage Audit

**Bead:** sf-e5q · **Date:** 2026-05-14 · **Depends on:** sf-fiz (host inventory)

> Scope: catalog `tests/`, map it against the host/service inventory, identify
> realistic gaps and cheap wins. NixOS lets us boot real systems in VM tests;
> they cost minutes per run but exercise the actual modules.

---

## TL;DR

- **Three** VM tests run on `nix flake check` (`minimal`, `network`, `working-vm`).
  Two more (`simple-vm-test.nix`, `kimb-services-integration-test.nix`) live in
  `tests/` but are **not wired into the flake** — they only run if invoked
  manually with `import ./tests/...` and have bitrotted accordingly.
- **`tests/integration-vm-test.nix` is dead code.** It references
  `./test-keys/test-ssh/*` which does not exist, and exposes itself under
  `.#tests.integrationTest` / `.#tests.unitTests.*` — flake attributes that are
  also not exported anywhere. `tests/run-tests.sh` calls those non-existent
  attributes. None of it has run in a long time.
- **Eight `eval-<host>` checks** cover NixOS-host evaluation (toplevel build),
  which is the most useful cheap signal we have today. Buildbot-nix builds these
  on every commit. **`mochi` and `oracle` (system-manager hosts) have no eval
  check** — a syntax error in either ships unnoticed until deploy.
- **Zero tests assert real host behaviour.** Every VM test uses generic
  `router`/`server` configs with `kimb.services` populated by hand. None imports
  an actual host config (`hosts/maitred/configuration.nix`, etc.), so a real
  host can break in ways no test catches.
- **Zero security/hardening tests.** Nothing checks port exposure, secret
  decryption against the real `secrets.nix` recipient list, `systemd-analyze
  security` scores, or that public services actually reach the public.

Recommended quick wins are in §5. The biggest single payoff is **(QW-2)**:
secret-decryption smoke per host, ~30 LoC each, catches the recurring agenix
recipient-mismatch class of bug.

---

## 1. Inventory: `tests/`

| File | Lines | Wired in `flake.checks`? | What it asserts | Notes |
|---|---:|---|---|---|
| `minimal-test.nix` | 15 | ✅ `minimal-test` | A single VM reaches `multi-user.target` | Smoke test of the harness itself, not the flake. |
| `working-vm-test.nix` | 69 | ✅ `working-vm-test` | Two VMs (`router`, `server`) on `10.200.0.0/16` boot, run sshd, ping each other, `:22` is listening | No kimb modules imported. Pure NixOS networking sanity. |
| `network-test.nix` | 239 | ✅ `network-test` | Same two-VM topology, **imports `modules/kimb-services.nix`**, configures `reverse-proxy`/`blog`/`homeassistant`, runs an nginx that returns canned strings, verifies cross-VM curl | First test that actually touches a kimb module. Does **not** assert any of the module's *computed* attributes. |
| `simple-vm-test.nix` | 155 | ❌ orphan | Two VMs + inline SSH keypair, asserts SSH between them works | Useful as a key-deployment example but redundant with `working-vm-test` for coverage. |
| `kimb-services-integration-test.nix` | 155 | ❌ orphan | Same two-VM topology, imports `kimb-services.nix`, threads `kimb.computed.servicesWithIPs` into the test script via `testScript = { nodes, ... }: …`. Asserts services listen on the configured port. | The closest thing we have to a real module test. **Should be wired into `flake.checks`** — it's the only one that exercises the computed attribute path. |
| `integration-vm-test.nix` | 548 | ❌ broken | Defines `integrationTest`, `unitTests.testServiceIPResolution`, `unitTests.testEnabledServiceFiltering`. Reads `./test-keys/test-ssh/*` which **doesn't exist on disk**. Exposes itself as `.#tests.*` — also not in any flake output. | Dead. See §6. |
| `README.md` | 98 | n/a | Documents the (dead) `.#tests.*` workflow | Misleading: describes infra that no longer evaluates. |
| `run-tests.sh` | 34 | n/a | Calls `.#tests.unitTests.*` and `.#tests.integrationTest.driver` | Dead. Both attrs are missing. |

### `flake.checks.x86_64-linux` — what actually runs in CI

```
minimal-test           ← tests/minimal-test.nix
network-test           ← tests/network-test.nix
working-vm-test        ← tests/working-vm-test.nix
eval-historian         ← config.system.build.toplevel
eval-marshmallow
eval-bartleby
eval-total-eclipse
eval-maitred
eval-rich-evans
eval-cheesecake
eval-donut
```

That's it. No `eval-mochi`, no `eval-oracle`, no darwin eval, no
`kimb-services-integration-test`.

---

## 2. Cross-check: hosts × tests

Host inventory derived from `flake-modules/nixos-configurations.nix`,
`flake-modules/darwin-configurations.nix`, `flake-modules/system-manager.nix`,
and `hosts/nebula-registry.nix`.

| Host | Variant | Eval-checked | VM-tested as itself | Notes |
|---|---|---|---|---|
| cheesecake | NixOS (Surface 3) | ✅ | ❌ | |
| donut | NixOS (Jovian / Steam Deck) | ✅ | ❌ | |
| historian | NixOS desktop | ✅ | ❌ | |
| total-eclipse | NixOS desktop | ✅ | ❌ | fish-shell host (gotcha) |
| marshmallow | NixOS laptop (T490) | ✅ | ❌ | |
| bartleby | NixOS laptop | ✅ | ❌ | |
| rich-evans | NixOS server | ✅ | ❌ | runs life-coach, copyparty, HA, kokoro, etc. fish shell. |
| maitred | NixOS router | ✅ | ❌ | Caddy, authelia, containers. Biggest blast radius if broken. |
| mochi | system-manager (Android/proot?) | **❌** | ❌ | New as of `feat(mochi)` commit 93423e3. Has no eval. |
| oracle | system-manager (Ubuntu VM, lighthouse) | **❌** | ❌ | Already burned us on cert re-encryption. |
| tachikoma | (registry-only) | n/a | ❌ | No NixOS config in tree. |
| darwin hosts | nix-darwin | ❌ | ❌ | Not evaluated by `nix flake check`. |

**Coverage of "this host actually evaluates" is good for NixOS, zero for
system-manager and darwin.**

### Cross-check: services × tests

Public ingress per `services/default.nix` (everything Caddy serves under
`*.kimb.dev`):

| Service | Subdomain | Backed by | publicAccess | Has reachability test? |
|---|---|---|---|---|
| reverse-proxy | www | maitred (container) | ✅ | ❌ |
| blog | blog | maitred (container) | ✅ | ❌ |
| authelia | auth | maitred (container) | ✅ | ❌ |
| homepage | home | maitred | ✅ | ❌ |
| grafana | grafana | maitred | ✅ | ❌ |
| prometheus | prometheus | maitred | ✅ | ❌ |
| matrix | matrix | rich-evans | ✅ | ❌ |
| homeassistant | hass | rich-evans | ✅ | ❌ |
| copyparty | files | rich-evans | ✅ | ❌ |
| jellyfin | media | historian | ✅ | ❌ |
| buildbot | buildbot | rich-evans | ✅ | ❌ |
| life-coach-dashboard | coach | rich-evans | ✅ | ❌ |

`network-test.nix` curls a *simulated* nginx, not the real service module, so
"reverse-proxy actually proxies the right thing to the right backend" is
unverified.

### Cross-check: modules × tests

| Module | Imported by any test? |
|---|---|
| `modules/kimb-services.nix` | ✅ (network-test, kimb-services-integration-test [orphan]) |
| `modules/nebula-node.nix` | ❌ |
| `modules/agenix.nix` | ❌ |
| `modules/restic-backup.nix` | ❌ (the staleness probe is on rich-evans; never exercised) |
| `modules/observability.nix` | ❌ (textfile collector + alerts; never exercised) |
| `modules/distributed-builds.nix` | ❌ |
| `modules/sre-agent.nix` | ❌ |

---

## 3. What the existing tests actually prove

Reading the test scripts strictly:

- A NixOS VM boots and reaches `multi-user.target`. (minimal-test)
- Two VMs on the same QEMU LAN can ping each other and run sshd. (working-vm-test)
- The `kimb-services` module *evaluates* with a couple of services configured,
  and we can stand up nginx and curl it cross-VM. The kimb module's computed
  attributes (`servicesWithIPs`, `enabledServices`, …) are not actually asserted
  in the test script. (network-test)
- The `eval-<host>` checks prove the toplevel system closure builds for eight
  NixOS hosts. This is what catches "I broke nebula-registry" or "I renamed an
  option" — most real CI value lives here, not in the VM tests.

What is **claimed** to be tested (per `tests/README.md`) but actually isn't:

- "Agenix encryption/decryption works in VMs" — only in the broken
  `integration-vm-test.nix`.
- "Services use `lib.mapAttrs`/`lib.filterAttrs` correctly" — only in the broken
  unitTests.
- "Service registry working" — only loosely; nothing asserts the computed
  values match `nebula-registry.nix`.

---

## 4. Gaps that have already cost us

Going back through recent fixes and `CLAUDE.md` gotchas, these are the bug
categories no test catches today:

1. **Agenix recipient drift.** "no identity matched any of the recipients"
   recurs when a host key rotates or a new host is added. There is no test that
   builds the real `secrets.nix` graph and asserts every secret has at least one
   recipient that matches a known host key.
2. **Reverse-proxy + new service.** Adding a `kimb.services.foo` entry to
   `services/default.nix` doesn't fail eval if `subdomain` collides or `host`
   points at a non-existent registry node. Caddy will silently end up with two
   vhosts for the same domain.
3. **Restic staleness.** The staleness probe is asserted via Prometheus alerting
   only. We have no test that the probe actually exports the metric (the
   textfile collector path is fragile).
4. **Port exposure.** The firewall config per host is hand-rolled; nothing
   asserts "maitred listens on 80/443 and nothing else from the WAN".
5. **System-manager hosts (mochi, oracle).** Not even an eval check. A typo
   ships.
6. **Cross-flake-input changes.** `org-life-coach` and friends are runtime
   inputs; bumping them can break `rich-evans`. The eval-rich-evans check
   catches *evaluation* but not *behavioural* regressions in the dashboard.

---

## 5. Recommended additions (quick wins)

Effort is rough wall-clock: S = afternoon, M = 1 day, L = multi-day.

### QW-1 — Add `eval-mochi` and `eval-oracle` to `flake.checks` · **S**

```nix
eval-mochi  = self.systemConfigs.mochi.config.system.build.toplevel;
eval-oracle = self.systemConfigs.oracle.config.system.build.toplevel;
```

(Exact path needs verification — system-manager's attribute name may be
`activationPackage`.) Effort is finding the right attribute, not the work.

**Catches:** typos / evaluation-time errors in the only two hosts we currently
deploy *blind*.

### QW-2 — Per-host secret-decryption smoke · **S each, can templatize · M total**

Pattern: one VM test per host that:

1. Builds the real host config from `nixosConfigurations.<host>`.
2. Overrides `age.identityPaths` to point at a test SSH host key.
3. Adds that test SSH key to `secrets/secrets.nix` recipients under a
   `tests`-only bootstrap path.
4. Boots the VM, asserts every `age.secrets.*.path` exists and is non-empty.
   Does **not** assert content — just that decryption succeeded.

**Catches:** recipient drift, mode/owner mistakes, missing secret files. ~30
LoC of testScript plus a tiny module.

### QW-3 — Public-vhost reachability test on maitred · **S**

VM test that imports the real `hosts/maitred/configuration.nix` (with networking
trimmed for the QEMU environment) and asserts:

- For every entry in `kimb.computed.serviceDomains` where `publicAccess = true`,
  Caddy resolves the vhost (`caddy adapt --validate` is enough; the test
  doesn't need to actually serve TLS).
- No duplicate vhost name across hosts (would mean two services claiming the
  same subdomain).

**Catches:** subdomain collisions, missing reverse-proxy entries for
remote-host services. Faster than booting Caddy.

### QW-4 — Port-exposure invariants · **S per host · M total**

For each host with a defined "wanted ports" list:

```nix
machine.succeed("ss -tnlp '! src 127.0.0.1' | awk '{print $4}' | grep -oE ':[0-9]+$' | sort -u")
```

…and assert the set equals an explicit allowlist (`{:22, :80, :443}` for
maitred from the WAN side, etc.). One VM, one assertion per role.

**Catches:** accidental world-exposure of an internal service after a refactor.

### QW-5 — Wire `kimb-services-integration-test` into `flake.checks` · **S**

It's already written; it asserts service-port reachability against the actual
`kimb-services.nix` module. Add it as a flake check and let buildbot-nix run it.

```nix
kimb-services-integration = import ./tests/kimb-services-integration-test.nix { inherit pkgs; };
```

### QW-6 — `systemd-analyze security` threshold gate · **S–M**

For a small allowlist of units (Caddy, Authelia, life-coach, copyparty), run
`systemd-analyze security <unit>` in the build VM and assert the score is below
some threshold (e.g. ≤6.0). One test, one threshold, easy to ratchet down over
time.

**Catches:** hardening regressions when modules drop `NoNewPrivileges` or
similar, which has happened upstream.

### QW-7 — Observability textfile-collector unit test · **S**

The restic-staleness probe writes to `/run/prometheus-node-exporter/textfile/`.
A VM test that runs the probe once and greps for
`restic_backup_staleness_seconds` in the output proves the metric path is
intact. Fast.

---

## 6. Recommended additions (expensive but valuable)

### LV-1 — Full nebula-mesh boot · **L**

3-VM topology: lighthouse + 2 nodes, real nebula-node module, real certs from
a test CA. Assert nodes reach each other over 10.100.0.0/16 and that
`groups`/firewall rules in the registry actually constrain traffic.

Cost: 5–10 minutes per CI run, real complexity in cert generation. Value: the
nebula firewall is the single largest piece of untested security surface in the
flake.

### LV-2 — Multi-host integration: maitred ↔ rich-evans · **L**

Boot a stripped maitred (Caddy + authelia containers) and a stripped rich-evans
(authelia stub, HA stub), assert authentication round-trip works through
Caddy's `forward_auth`. This is the cheapest acceptable proxy for "did I break
SSO?", which is currently impossible to test outside production.

### LV-3 — Buildbot-nix pre-flight harness · **L**

A meta-check that evaluates `nix flake check` *on a synthetic merge commit*
that mutates `nebula-registry.nix` (e.g. add/remove a host) and verifies the
graph still closes. Catches the class of bug where a registry change makes some
other host fail to eval. Complex to express, but high value because the registry
is the most-touched single file in the repo.

### LV-4 — Darwin eval checks · **M**

`darwin-configurations.<host>.system.build.toplevel` exposed as flake checks on
`aarch64-darwin`. Requires CI to actually have a darwin builder; if not, at
least add them as a job on a developer machine. Catches mac-side breakage that
otherwise only surfaces during `darwin-rebuild switch`.

---

## 7. Dead code to remove (separate PR)

Recommend filing as a follow-up cleanup bead — out of scope for this audit, but
worth flagging here so it doesn't get re-baselined:

- `tests/integration-vm-test.nix` — references `tests/test-keys/` which doesn't
  exist; exposes attributes (`.#tests.integrationTest`, `.#tests.unitTests.*`)
  that aren't flake outputs. Has never run in this form.
- `tests/run-tests.sh` — invokes `.#tests.*` attributes; broken in the same way.
- `tests/README.md` — documents the dead `.#tests.*` workflow and the
  test-keys/ infrastructure that doesn't exist. Misleading.
- `tests/simple-vm-test.nix` — redundant with `working-vm-test.nix`; if it had
  unique value we'd wire it in. Considered for removal.

The secret files (`secrets/test-nebula-*.age`, `secrets/test-ssh-*-key.age`) are
**still wired** to the broken `integration-vm-test.nix` only. If that file is
deleted, audit whether anything else consumes them (likely nothing) and drop.

---

## 8. Prioritized recommendation summary

| Rank | Item | Effort | Why |
|---|---|---|---|
| 1 | QW-2 secret-decryption smoke | M | Catches the highest-recurring class of deploy-time failure. |
| 2 | QW-1 eval-mochi / eval-oracle | S | Trivial; closes the two un-evaluated hosts. |
| 3 | QW-5 wire kimb-services-integration-test | S | Already written; flip a switch. |
| 4 | QW-3 maitred vhost reachability | S | Catches subdomain collisions silently introduced by `services/default.nix`. |
| 5 | QW-4 port-exposure invariants | M | Cheap, prevents future internet-exposure incidents. |
| 6 | QW-6 systemd-analyze gate | S–M | Hardening ratchet. |
| 7 | LV-1 full nebula-mesh test | L | Largest untested security surface; do once the QW set is in. |
| 8 | QW-7 observability probe smoke | S | Single metric; fast. |
| 9 | LV-2 maitred ↔ rich-evans auth flow | L | Catches the SSO break. |
| 10 | LV-4 darwin eval | M | Only if a darwin builder is reachable from CI. |
| — | LV-3 registry-mutation pre-flight | L | Speculative; reconsider after item 1 lands. |

Cleanup (§7) can land in parallel with QW-5 — same area of the tree.
