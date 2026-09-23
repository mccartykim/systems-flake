# Lifecoach handoff — after the bridge-crew removal

**Date:** 2026-09-23
**Context:** The 40k "bridge officer" roleplay stack was removed from this
flake wholesale, so a simpler lifecoach can be built without 11 character
agents in the tree. This document is the briefing for whoever (human or
agent) writes that next lifecoach.

---

## 1. What was removed

### Flake inputs (gone from `flake.nix`)

| Input | What it was |
|---|---|
| `bridge-crew` | Aggregator flake. Its 13 members were **11 officer characters** (void-master, factotum, confessor, explorator, chirurgeon, interrogator, remembrancer, savant, choirmaster, factor, navigator) **+ lifecoach-organism + vacuum-organism**. |
| `bridge-crew-src` | `mccartykim/40k_bridge`, `flake = false`. Source tree for the `org-bridge` broker, `vox-bridge`, and the Phase-2 `vox-organism` ("Astropath") daemon, imported by path string. |
| `organism` | The stateful-agent CLI (`bin/organic`). Was a *root* input only for the vox daemon's `organicBin`. **It still exists** in `flake.lock` as a nested input of `lifecoach-organism` and `vacuum-organism` — no root-level declaration is needed. |

### Inputs added

| Input | Why |
|---|---|
| `lifecoach-organism` | `mccartykim/lifecoach_organism` — your live lifecoach, previously reached through `bridge-crew.nixosModules."lifecoach-organism"`. Now a direct root input. |
| `vacuum-organism` | `mccartykim/vacuum_organism` — the vacuum sidekick, same treatment. |

Both are self-contained flakes: `nixosModules.default` resolves their own
package from `pkgs.system`, so they need no `extraSpecialArgs` and no colmena
`meta.specialArgs`.

### Deleted files

Officer host-enablement files on rich-evans:
`voidmaster-organism.nix`, `voidmaster-vox-bridge.nix`, `vox-organism.nix`,
`factotum-organism.nix`, `confessor-organism.nix`, `explorator-organism.nix`,
`chirurgeon-organism.nix`, `interrogator-organism.nix`,
`remembrancer-organism.nix`, `savant-organism.nix`, `choirmaster-organism.nix`,
`factor-organism.nix`, `org-bridge.nix`, `email-digest-stub.nix`.

On historian: `navigator-organism.nix`, `bridge-scribe.nix`, and the whole
bridge-scribe python suite (`bridge_scribe_{dispatch,materialize,read,sync}.py`,
`test_bridge_scribe*.py`).

### Disabled / relocated

- **Forgejo** — was the officers' Nebula-only PR surface (`#forge`). Its module
  is no longer imported; the config file moved to `../crew_secrets/forgejo.nix`
  for reference. It was never wanted for its own sake.
- **`secrets/`** — four officer-only `.age` files moved to `../crew_secrets/`
  (sealed, unreferenced). See §4.

### Reverted: the Phase-4 Chirurgeon handoff

`hosts/rich-evans/lifecoach-organism.nix` had the lifecoach in a cutover where
**the Chirurgeon officer was the sole nudger**: `lifecoach-heartbeat` ran with
`LIFECOACH_ASSIGN_ONLY=1` (light overdue LEDs, stop — no speak/vision/judgment)
and `lifecoach-scheduler.timer` was `wantedBy = []`.

With the Chirurgeon gone, both are unwound: the `LIFECOACH_ASSIGN_ONLY` env and
the `stop-lifecoach-proactive` activation script are deleted, restoring full
proactive lifecoach behavior. The reactive sidecars (button-monitor, dashboard,
discord-bot, watchdog) were never gated on that block.

---

## 2. What survives, and why

`org-agent` and `org-life-coach` are **not** 40k roleplay and were left in place:

- **`org-agent`** — the emacs/org-mode agent framework. It provides the emacs
  daemon and `elisp/init.el` the lifecoach calls for task views and org-task
  write verbs. Still a root input, still used.
- **`org-life-coach`** — the *older* python lifecoach daemon
  (`hosts/rich-evans/org-life-coach.nix`). Currently its own services are
  `lib.mkForce`-disabled (lifecoach-organism replaced it) but **its emacs daemon
  is kept running on purpose** — `lifecoach-organism.nix` points
  `orgAgentSocket` at `/var/lib/life-coach-agent/emacs/org-agent`.
- **`org-crm`** — the Secretary CRM bot. Independent of the officers.

---

## 3. Current lifecoach state (the thing you're replacing)

`services.lifecoach-organism` is enabled on rich-evans and reads its
configuration from `hosts/rich-evans/lifecoach-organism.nix`:

- state: `/var/lib/lifecoach-organism` (untouched by this removal)
- HA token: reuses `ha-life-coach-token.age` via `life-coach.nix`
- models: `deepseek-v4.1-flash:cloud` (main), `gemma4:31b-cloud` (judgment + vision)
- TTS: `http://historian.nebula:8091`, voice `jet2`, device "Kim's nest hub"
- dashboard: `0.0.0.0:8586` (LAN/Nebula only; firewall rule in
  `hosts/rich-evans/configuration.nix`, vhost in `services/default.nix`)
- cameras: `127.0.0.1:8554/cam0` (bed), `/cam1` (desk)

**Runtime state is safe.** Everything lives outside the repo in `/var/lib/*`.
Deleting or rewriting Nix config never touches it.

---

## 4. Moved secrets

In `../crew_secrets/` (outside the repo, sibling to `systems-flake`):

| File | Was |
|---|---|
| `matrix-vox-bridge-token.age` | `@vox-bridge:kimb.dev` Matrix access token |
| `bridge-fleet-ssh-key.age` | rich-evans vox daemon → historian bridge-scribe hop |
| `deploy-key-bridge-scribe.age` | bridge-scribe GitHub deploy key (account key, broad write) |
| `forge-bot-token.age` | forgejo application token |
| `forgejo.nix` | the forge's module config (not a secret) |

All stanzas were deleted from `secrets/secrets.nix` — a dangling owner (e.g.
`owner = "vox-organism"`) breaks evaluation once the officer service users are
gone, since those users were created by the now-removed modules.

**Stayed in place** (not officer-only): `discord-vacuum-bot-token.age` (the
vacuum sidekick, still live), `ha-life-coach-token.age` (shared, still used),
`matrix-life-coach-token.age`, `discord-life-coach-token.age`.

If you re-key or recreate an officer, the sealed `.age` values are still in
`crew_secrets/` — but note the GitHub deploy key had broad `mccartykim/*` write
scope and is worth revoking on GitHub if you never intend to use it again.

---

## 5. Notes for the next lifecoach

### Dangling forced-command key entries

Two places authorize the old fleet-internal key by pubkey
(`ssh-ed25519 AAAA…IJkCorkwI7RWuRNFg241GpMSj2ZE2rxgF+IPoPF7E8wN`):

- `hosts/historian/kdeconnect-sms.nix` — the `sms-history` reader
- `hosts/total-eclipse/sms-history.nix` — same reader (the key is baked into
  that file's `fleetKey` string too)

Their only consumer was the vox-organism daemon's officer cycles. They are left
in place deliberately — the `sms-history` reader is plausibly useful to a
lifecoach that wants to know about unread texts, and re-issuing the key entry is
churn until the new design settles. **If you re-key, remove these entries.**

### `sms-history` is a ready-made tool

`sms-history` (KDE Connect SMS reader, forced-command, read-only, JSONL out)
already exists and is designed to be called over ssh. If the simpler lifecoach
wants "did anyone text me", this is the plumbing.

### Vacuum sidekick

`services.vacuum-organism` survives. Note `hosts/rich-evans/vacuum-organism.nix`
still puts `life-coach` in the `vacuum-organism` group so the lifecoach's
`dispatch-robot` wrapper can write `dispatch.org`. The reverse grant (the
Chirurgeon's `vox-organism` group membership) was removed.

### Removed plumbing you may or may not want back

- **`org-bridge`** — a SO_PEERCRED-authenticated broker between officer agents
  and `~/org`. It was how officers read/wrote the org tree without full user
  trust. A lifecoach that touches org files directly may not need it.
- **`bridge-scribe`** — the forced-command "authoring servitor" on historian
  that cloned/committed/pushed PRs on an officer's behalf. Pure officer
  infrastructure; nothing else used it.
- **Officer uids 987–998** — created by the removed modules, so they no longer
  exist in config. Any live `/run/agenix` files owned by `vox-organism` etc.
  disappear on the next `nixos-rebuild switch`/`colmena apply`.

### Verification performed

- `nix eval .#nixosConfigurations.{rich-evans,historian,total-eclipse,maitred,creme,cheesecake,donut,marshmallow,bartleby}.config.system.build.toplevel.drvPath` — all evaluate.
- `nix eval .#colmena.rich-evans.deployment.targetHost` — evaluates.
- `flake.lock` regenerated: 219 → 118 nodes, **zero** officer nodes.
- `media-classifier` verified independent: its lock node lists only `nixpkgs`.
