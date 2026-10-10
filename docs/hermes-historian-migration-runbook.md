# Hermes → historian migration runbook (Phase 2 cutover)

**Owner:** systems-flake-mgr · **Status:** READY — gated on @kimb's §5 calls (PRD
`docs/hermes-historian-migration-prd.md`) and the go for the cutover window.
**Change-set:** `hosts/historian/hermes-agent.nix` + flake input `hermes-agent` +
agenix `hermes-env.age` / `hermes-dashboard-session-token.age` (this repo).

## 0. Preconditions

- [ ] @user go/no-go: single-writer (historian canonical), car/ payload, TE
      Maildir retirement window (PRD §5). Telegram tokens optional — shared-bot
      `profile_routes` works without them; tokens land later via
      `agenix -e` + redeploy.
- [ ] historian disk: `ssh historian.nebula 'df -h /'` — expect ≥100G free
      (first uv2nix build is chunky; if tight → `nh clean all -K 2d` FIRST,
      then expect the next apply to be slow per the post-gc tradeoff).
- [ ] Workspace transport **done 2026-10-10 (git, supersedes Syncthing):** bare repo
      `/mnt/media-drive/job_search_mk2.git` + canonical working tree
      `/mnt/media-drive/job_search_mk2` + per-folder symlink
      `mkdir -p /home/kimb/shared_projects && ln -s /mnt/media-drive/job_search_mk2 /home/kimb/shared_projects/job_search_mk2`
      (JC's handoff §2 form; the whole-drive variant is superseded).
      Verified live: baseline `7222ebc` (382 files), `job-search.org` sha256
      `64506f52…` identical on both hosts, tree clean. TE's clone is
      push-wired (`origin = kimb@historian.nebula:/mnt/media-drive/job_search_mk2.git`).
- [ ] B2 proof: `sudo cat <staticPaths store file>` shows
      `/mnt/media-drive/job_search_mk2` **and** `/mnt/media-drive/job_search_mk2.git`
      (the bare repo got its own line 2026-10-10 — a sibling of the working tree,
      not covered by it; pending the next historian apply to land in the live set).

## 1. Deploy the module (historian builds its own closure)

```bash
ssh kimb@historian.nebula
cd ~/projects/systems-flake
jj git fetch && jj new main && git rev-parse HEAD   # verify == pushed main
# provenance guard: the deploy must carry this change-set
git show --stat HEAD | grep hermes-agent.nix || echo "STALE TREE — stop"
# dry-activate builds + pushes the closure; the apply then just activates
nix develop -c colmena apply --on historian dry-activate
nix develop -c colmena apply --on historian          # activates
```

Run detached (no `timeout` wrapper — killed builds restart from scratch and
orphan store-realise processes pin disk): write the two applies into
`/tmp/hermes-deploy.sh`, launch `setsid bash /tmp/hermes-deploy.sh >
/tmp/hermes-deploy.log 2>&1 < /dev/null &`, poll the log for `=== DONE`.

**Post-deploy probes (empty-state sanity, NOT the migration):**
- [ ] `systemctl status hermes-agent hermes-backend` — both active, kimb user.
- [ ] `hermes doctor` as kimb on historian (via ssh) — fresh empty HERMES_HOME
      should pass with zero profiles.
- [ ] `ss -tlnp | grep 9119` — backend bound on the nebula IP.
- [ ] `sudo -u kimb curl -s -o /dev/null -w '%{http_code}' http://historian.nebula:9119/` — 401/redirect = auth gate engaged (expected; creds below).

## 2. Cutover — move the durable state

**Stop the source first** (a live copy misses WAL-resident writes; sessions
optimize/prune refuse while a process holds the DB):

```bash
# on total-eclipse: quit the Hermes desktop app + gateway (interactive
# install — no systemd unit; pgrep hermes to confirm nothing holds state.db)
pgrep -af 'hermes serve|hermes-desktop'   # then quit via the app, or:
# pkill -f 'hermes serve'  (the desktop app restarts its own backend — quit the app)
```

**rsync the durable set** (86M; re-fetchables stay behind — never rsync
`cache/ logs/ hermes-agent/ tools/`):

```bash
rsync -av --chown=kimb:users \
  --exclude 'cache' --exclude 'logs' --exclude 'hermes-agent' --exclude 'tools' \
  --exclude 'models_dev_cache.json' --exclude 'pets' --exclude 'telemetry' \
  /home/kimb/.hermes/ historian.nebula:/var/lib/hermes/.hermes/
```

The activation-rendered files (`config.yaml`, `.env`, `.managed`) are owned by
the module — rsync with `-a` preserves the source's, but activation re-renders
them from `settings` + `environmentFiles` on every switch, so the rsynced
copies are transient. Per-profile dirs (incl. each profile's own `.env`,
`config.yaml`, skills, memories, sessions, state.db) ride verbatim — the module
never touches them.

**Restart + verify on historian:**

```bash
sudo systemctl restart hermes-agent hermes-backend
hermes profile list        # expect: blog-pm, facade-decomper, jobcoach, knitwork-pm, systems-flake-mgr (+ default)
hermes sessions list --profile jobcoach | head    # session history present
systemctl status hermes-agent hermes-backend
```

- [ ] `hermes profile list` shows all five.
- [ ] jobcoach session history + skills load (`hermes skills list --profile jobcoach`).
- [ ] Digest probes: `mu`-free — the profiles' own credentials ride the rsync.

## 3. Access topology after cutover

- **Desktop app (laptops/phone-side):** add a Remote gateway
  (Settings → Gateways): host `historian.nebula`, port 9119, and the
  **session token** (`hermes-dashboard-session-token` in the §4 handoff dir) —
  the app then runs against historian's backend, same sessions everywhere.
  (The session-token file is read server-side by the backend launcher; the
  desktop app takes its copy in the gateway-connection settings.)
- **Dashboard:** `http://historian.nebula:9119/` — nebula-only; basic-auth
  username `kimb`, password in the handoff below. OAuth (Nous Portal) is the
  upgrade path if ever exposed publicly (then a maitred caddy vhost +
  authelia per the services/default.nix pattern, PRD Q9 later phase).
- **Workspace editing surface (git transport, supersedes Syncthing):** canonical
  tree `/mnt/media-drive/job_search_mk2` on historian, reachable byte-identically
  via `/home/kimb/shared_projects/job_search_mk2`. Emacs-on-TE edits via
  tramp/ssh; edits land on the historian tree, committed there (or from TE via
  pull→edit→push). TE's local clone is read-only-by-rule — history only advances
  by push to `origin` (`kimb@historian.nebula:/mnt/media-drive/job_search_mk2.git`).
  Offline fallback: edit locally in TE's clone, `git push` when networked.
- **Telegram:** tokens pending @user (one bot per profile) — without them the
  gateway runs serve-mode + Discord platforms fine (per-profile .env carries
  existing Discord tokens from the rsync). Adding a token later =
  `agenix -e hermes-env.age` on TE→... no — tokens are per-PROFILE .env,
  which the module does not manage: edit
  `/var/lib/hermes/.hermes/profiles/<name>/.env` directly on historian, then
  `systemctl restart hermes-agent`.

## 4. Secrets handoff for @user (plaintext NOT in the repo)

- Dashboard basic-auth password (generated, scrypt-hashed in the env secret —
  plaintext lives in the age file and the local handoff file only):
  `/home/kimb/.hermes/profiles/systems-flake-mgr/cache/scratch/hermes-secrets/DASHBOARD_PASSWORD.txt` (0600).
- Desktop app remote-gateway token: same dir, `hermes-dashboard-session-token` file.
- Rotate anytime: `agenix -e hermes-env.age` (password hash) + redeploy.

## 5. Rollback

- Deploy-level: `nix-env --switch-configuration` / colmena apply of the
  previous generation (`system-296-link` is pre-Hermes as of writing).
- State-level: total-eclipse's `~/.hermes` is untouched (Phase 3 retirement is
  gated on a multi-day soak); worst case = repoint the desktop app at a
  re-created local backend on TE. The rsync was one-way — nothing on TE was
  modified by the migration.

## 6. Post-migration (Phase 3, gated on soak)

- [ ] Multi-day soak: daily `systemctl status` probes + a JC-side sweep
      against the canonical store (his freshness gate, reader-only).
- [ ] TE Maildir retirement (30G back to /mnt/bulk) — @user's call per PRD §5.4.
- [ ] rich-evans INBOX residue cleanup (PRD §3.3 recipe) — after the first
      post-seed B2 snapshot proves the canonical store restic-covered.
- [ ] Optionally decommission TE's interactive Hermes install (keep as
      rollback until confident).