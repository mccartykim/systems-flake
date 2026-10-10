# PRD: Hermes → historian migration, incl. email convergence

**Author:** systems-flake-mgr (fleet half); jobcoach owns the workspace half (.stignore + handoff note, slotted into Phase 1).
**Written:** 2026-10-10, after live verification on total-eclipse, historian, and rich-evans.
**Status:** DRAFT — awaiting @kimb go/no-go (§5). **Phase 0 flake fixes are now implemented in the tree** (timer, mount guard, orgNotesDir bind, gmail parity — see §4.0); Phase 1's restic line landed with them.

## 1. Problem

Hermes (desktop + gateway, 5 agent profiles incl. jobcoach) runs on total-eclipse, forcing the gaming PC to stay powered on. Job coach's working state is split across three places with uneven protection: its "brain" (profile dir), its workspace (`job_search_mk2`), and its mail (a 30G Maildir). Verified this week: the workspace and TE's Maildir both live on `/mnt/bulk`, which has **no offsite backup** (restic doesn't traverse the `~/shared_projects` symlink; `/mnt/bulk` has no extraPaths line) — and the only B2-covered mail copy, historian's twin Maildir, was 15 days stale because the index service was wedged (§2.3).

Goal: one Hermes deployment on historian as a flake-managed service; job coach's brain, workspace, and mail all landing on historian with systematic B2 coverage; total-eclipse free to power off; phone/laptop access via Telegram + remote gateway.

## 2. Verified current state (2026-10-10, live)

### 2.1 Hermes on total-eclipse
- Interactive install: electron desktop app + `hermes serve --host 127.0.0.1 --port 0` gateway (no systemd unit — migration day is "quit the app", not systemctl).
- 5 profiles: blog-pm, facade-decomper, jobcoach, knitwork-pm, systems-flake-mgr. Durable payload (minus `cache/`+`logs/`): 12–17M per profile, ≈75M total, +11M top-level state ≈ **86M to migrate**. The big dirs are re-fetchables (`hermes-agent/` 468M, `tools/` 460M, jobcoach `cache/` 103M) and are never rsynced (runbook: `references/hermes-on-historian.md`).
- Today `~/.hermes/` rides TE's `/home/kimb` restic include — safe *while TE stays on and backed up*, which is exactly the dependency we're removing.

### 2.2 Drives (lsblk, in vivo)
| Drive | Host / mount | Type | Free | Notes |
|---|---|---|---|---|
| Seagate Expansion SW 5.5T | historian `/mnt/media-drive` | **rust** (ROTA=1, not SMR) | 3.6T | hosts email-digest Maildir, org, tooms_photos, syncthing mesh |
| PNY PRO ELITE V2 931.5G | historian `/mnt/games` | **flash** (ROTA=0), USB, ext4 | ~869G | designated Steam/Proton volume, 410M used |
| Samsung 980 PRO 2T | historian `/` + `/nix/store` | NVMe | 126G (85% full) | mu xapian index (6.3G) lives here by design |
| ST4000DM004 3.6T btrfs | total-eclipse `/mnt/bulk` | rust | — | workspace + TE Maildir; NO offsite copy (hourly btrfs snapshots, ~48h retention, same disk) |

**The "rust cache" question is already answered by the existing design:** `hosts/historian/email-digest.nix` keeps the bulk Maildir on the seagate (mbsync writes sequentially — rust handles that fine) and the mu/xapian index on the SSD, where interactive random reads happen. The split layout is documented in the file and running today.

### 2.3 Email (the loose end) — two diverged 30G Maildirs, same 3 accounts (zoho/gmail/fastmail)
| | total-eclipse `/mnt/bulk/Mail` | historian `/mnt/media-drive/email-digest/Mail` |
|---|---|---|
| Pulled by | kimb's interactive `~/.mbsyncrc` | email-digest module mbsyncrc |
| Mode | `Create Both` + `Sync All` (two-way: flags/folders reach the servers) | `Create Near` + `Sync Pull` (pull-only) |
| Folder set | richer — zoho incl. `ZMNotification` (JC's sweeps depend on it), gmail incl. `Job Search`, `Junk`, `Unroll.me`, `Weirdo Newsletters` | zoho `Patterns *` (matches incl. ZMNotification); gmail narrower (7 explicit folders — **missing the 4 above**); fastmail `Patterns *` |
| Freshness | current (synced today; JC's Oct-9/10 sweep ran against it) | **15 days stale** — index service wedged |
| Backup | **none offsite** (on `/mnt/bulk`); its 7.2G mu index is restic-EXCLUDED (`.cache` pattern) | restic-covered (extraPaths); 6.3G mu index on SSD under `/var/lib` (covered) |

**Incident (found 2026-10-10; flake fixes implemented, deploy pending):** historian's `email-digest-index` (mbsync+mu) was wedged since **Sept 25 02:48** — a deploy SIGTERM'd a 44-min index run mid-pass; the `OnBootSec`+`OnUnitActiveSec` monotonic pair re-arms only from a *completed* activation, so the timer sat active with a blank `NextElapseUSecRealtime` while the hourly digest DM'd "No new mail" against a stale index. **Flake bugs fixed in the tree (verified against the pinned nixpkgs rev `7c43f080`):** (a) `RequiresMountsFor` was set under `serviceConfig` → lands in `[Service]` where systemd *ignores* it (journal: `Unknown key 'RequiresMountsFor' in section [Service], ignoring`) — there is **no** `requiresMountsFor` service option at this nixpkgs rev; the correct spelling is the unit-level `unitConfig.RequiresMountsFor` attr, now on both services; (b) the guarded path is now `/mnt/media-drive` (`/mnt/seagate` hasn't existed on historian since a3j.6); (c) `orgNotesDir` pointed at `~/shared_projects/org_crm/notes`, which doesn't exist on historian (actual: `~/projects/org_crm/notes`) — and even with the right path, `/home/kimb` is 0700 so the `email-digest` user gets EACCES (verified live); fixed with a read-only bind mount (`/var/lib/email-digest/org-notes` ← `~/projects/org_crm/notes`, the Jellyfin idiom); (d) the gmail channel was missing 4 folders TE's interactive mbsyncrc pulls (`Job Search`, `Junk`, `Unroll.me`, `Weirdo Newsletters` — ≈4.8k messages); patterns extended for parity. Index timer switched to `OnCalendar=hourly` + `Persistent=true` — a calendar timer always has a future elapse after a restart. **Lesson for all deploy checklists:** `OnUnitActiveSec` + oneshot killed mid-run = wedged timer; check `systemctl show <timer> -p NextElapseUSecRealtime` after any deploy that restarts one.

### 2.4 Workspace & transport
- `job_search_mk2` (115M; core 14M without `car/` 101M — 67M Haynes PDF + ~30M regenerable diagram scratch; hand-authored core ≈4M), `job-search.org` 207K actively edited.
- Syncthing TE↔historian healthy (connected; `~/org` 100% completion both directions). Folder config is UI-managed (`overrideFolders/Devices=false`) — adding a folder is a web-UI action on both ends, not a flake edit.
- `.polytoken/` is a 2-item dir (hooks.json) — needs an explicit `.stignore` decision (JC has it).

## 3. Target architecture

1. **Hermes service on historian** — as previously designed (skill ref `hermes-on-historian.md`): `github:NousResearch/hermes-agent` as a pinned flake input, `nixosModules.default` on historian, one gateway multiplexer serving all 5 profiles, state under `/var/lib/hermes` (rides the `/var/lib` restic include automatically), secrets via agenix + `environmentFiles`, Telegram one-bot-per-profile, dashboard nebula-only at first.
2. **Workspace** — Syncthing Send/Receive `job_search_mk2` → `/mnt/media-drive/job_search_mk2`, **historian canonical** (JC's single-writer rule for `job-search.org`), JC's `.stignore` + handoff note, plus one line: `kimb.restic.extraPaths += ["/mnt/media-drive/job_search_mk2"]` on historian. Path canonicalization via `ln -s /mnt/media-drive /home/kimb/shared_projects` on historian (JC's proposal — verified nothing exists at `~/shared_projects` there today, so no shadowing risk).
3. **Email: converge on ONE canonical Maildir on historian's seagate.**
   - The IMAP servers hold the truth (TE's mbsync is two-way: `Create Both` + `Sync All`), so this is a **catch-up pull, not a 30G migration**.
   - PNY stays the games volume: it's removable USB flash — the wrong home for a primary copy of irreplaceable mail — and there's no capacity or performance reason to move mail off the seagate (split layout already solves rust's random-read weakness; neither drive is SMR).
   - Concretely: fix §2.3's three flake bugs; extend historian's gmail channel `Patterns` with `"Job Search" "Junk" "Unroll.me" "Weirdo Newsletters"`; let mbsync catch up (sequential writes, rust-appropriate); jobcoach reads the canonical Maildir + **one shared mu index** via the email-digest group (the Interrogator precedent: group-read, `mu --muhome /var/lib/email-digest/.cache/mu`; hermes user joins `email-digest` group). One index, two readers, hourly freshness for JC's sweeps — no second 6-7G index on the SSD.
   - TE's Maildir becomes the rollback copy (kept on `/mnt/bulk`, 48h snapshots), retired after a verified catch-up + soak window.
4. **End state:** every piece of JC's world B2-covered *systematically* (brain via `/var/lib`, workspace via extraPaths, mail via existing extraPaths) rather than incidentally, and total-eclipse powers off.

## 4. Phases

**Phase 0 — email repair (hours; independent of everything else; recommended regardless):** flake fixes — `unitConfig.RequiresMountsFor = ["/mnt/media-drive"]` on both services (NOT a bare `requiresMountsFor` attr; no such option at the pinned nixpkgs rev), `OnCalendar=hourly` index timer, orgNotesDir corrected + ro bind mount (`/var/lib/email-digest/org-notes`), gmail Patterns parity — **implemented in-tree 2026-10-10, eval-gated** → deploy historian → catch-up sync + index → verify: timer `NextElapse` non-blank, digest DM shows real mail, and a known message (e.g. the Oct-9 08:26 LinkedIn "Bastion's Senior Software Engineer" alert from JC's sweep) findable via `mu find` on historian.

**Phase 1 — workspace + backup line (~1h + sync):** Syncthing folder both ends (UI), JC's `.stignore` + handoff note, `restic.extraPaths` line (**landed in-tree 2026-10-10** — safe pre-Syncthing: restic logs a warning and continues on an include path that matches no files, verified against restic 0.19.1), eval gate, deploy, live coverage re-audit (staticPaths file + one restic dry pass).

**Phase 2 — Hermes module + migration (one build session):** `nh clean all -K 2d` first (disk at 85%/126G free; uv2nix first build is chunky — 24 cores fine), pin input, module config, agenix secrets (bot tokens → `environmentFiles`), activate and verify empty, then cutover: quit TE gateway (WAL-safe rsync per runbook), rsync 86M durable set, chown to hermes user, verify (`hermes profile list`, sessions, `systemctl status`), Telegram bots live, laptops via remote gateway (Settings → Gateways).

**Phase 3 — retirement:** after a multi-day soak, delete TE Maildir (30G back to bulk), optionally decommission TE's interactive Hermes; keep TE `~/.hermes` as rollback until confident.

## 5. Decisions needed from @kimb (go/no-go)

1. **Phase 0+1 now?** Independent of the Hermes move; closes the workspace's offsite gap (the sharpest risk — irreplaceable, unprotected) and restores honest mail digests. Recommended: yes, now.
2. **Does `car/` ride?** (JC's question: keep `cars.org` + scripts, drop the 67M PDF + regenerable scratch → sync/B2 set drops 115M → 14M. Either works; the flake line doesn't change.)
3. **Single canonical Maildir on the seagate + PNY stays games?** (My recommendation: yes to both — see §3.3.)
4. **Hermes scope:** all five profiles? Telegram one-bot-per-profile (needs BotFather tokens from you) vs shared bot + `profile_routes`?
5. **TE Maildir retirement window** (I'd suggest: delete after Phase 0 verification + 2 weeks soak; it costs 30G of snapshot-covered bulk in the meantime).

## 6. Risks

- Hermes Nix packaging is Tier 2 best-effort: pin the input, bump deliberately, never as a nixpkgs-update rider; container mode is the fallback.
- Under the module, config becomes flake-managed (`.managed` marker blocks `hermes config set`) — profile config changes become flake edits.
- First uv2nix build on an 85%-full root: run after `nh clean all -K 2d`; expect slow, not substitution-fast, per the post-gc tradeoff.
- Wedged-timer pattern (§2.3) generalizes: after any deploy that restarts an `OnUnitActiveSec` oneshot, check `NextElapseUSecRealtime`.
- Two-way flag sync means the servers hold mail truth — but the rollback Maildir stays until the catch-up is *verified* against known messages (Phase 0 gate), not assumed.
