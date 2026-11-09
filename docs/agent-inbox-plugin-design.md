# Cross-workspace agent inbox — design notes

**Status:** DRAFT for review, 2026-11-09. Nothing here is built.
**Scope:** the four agent workspaces on `historian` — systems-flake, job search, grocery, OCD.

Terms used below:

- **DSH** — DeepSeek Harness, the agent host (version 0.2.1-rc.3 here).
- **Plugin row** — one entry in a host-local YAML file that loads a JS module. The Kagi
  search plugin uses this pattern.
- **`~/.dsh/cordis.patch.yml`** — the host-local plugin configuration layer. It applies to
  every profile.
- **HMR** — hot module reload; without it, a changed plugin needs a DSH restart.
- **Agent Teams** — the built-in feature that lets one session spawn named teammates and
  message them.
- **Market index** — the community plugin catalog at
  `https://cdn.jsdelivr.net/npm/dsh-plugin-catalog/index.json`.

## 1. What exists today

| Workspace | Root | Inbox |
|---|---|---|
| systems-flake | `/home/kimb/systems-flake` | `inbox.org` |
| job search | `/mnt/media-drive/job_search_mk2` | `inbox.org` |
| grocery | `/home/kimb/grocery_reminder` | `inbox.org` |
| OCD | `/home/kimb/ocd_study_workspace` | `inbox.org` |

- Each workspace has `inbox.org` and `inbox_archived.md`. Both are machine-local and
  gitignored (systems-flake, job search, grocery). OCD is not a git repository.
- Each workspace's agent instructions define the protocol. Another workspace is read-only,
  with one exception: an agent may append one org block to its `inbox.org`. The block
  states the ask, the proposed fix, diffs when useful, open questions, and "done when".
- A request is an intent. The owner accepts or rejects it. The owner processes its inbox
  only when Kim asks. It moves the whole block into `inbox_archived.md`, adds an outcome
  line, and deletes the block from `inbox.org`.
- Sessions run with different file policies. A `danger-full-access` session can append to
  another workspace's inbox. A `workspace-write` session cannot; it must put the block in
  its reply and Kim relays it. This was observed in the session logs on 2026-11-09.

## 2. Problem and goals

Problems:

- The protocol is text in four places. Format drift and missed steps are likely.
- The sandbox blocks the intended writer in `workspace-write` sessions.
- Every hand-off needs Kim in the middle. Kim says low-risk workspaces (grocery, OCD)
  could get "auto review" because the inbox has been reliable.

Goals:

1. One mechanical implementation of send, list, get, and archive.
2. It works from a `workspace-write` session.
3. It keeps the human-readable org format and the async intent model.
4. Optional auto-review for low-risk workspaces.
5. Kim keeps control of trust.

Non-goals:

- Auto-apply changes across workspaces. Each agent edits only its own files.
- A network service or message broker.
- Replacing Agent Teams for teammates spawned inside one session.

## 3. Options

| Option | Cost | Works from workspace-write | Notes |
|---|---|---|---|
| A. Status quo: files, prompt rules, manual relay | none | no | works today; drift and relay stay |
| B. Existing plugin | low | — | none fits; see below |
| C. Custom host-local plugin | medium | expected, to verify | privileged by design; small code |
| D. C plus auto-review | higher | expected | needs a trust policy and limits |

Why no existing plugin:

- Agent Teams messages only reach teammates spawned inside one session. The four
  workspaces are independent sessions.
- The market's `dsh-eteams` plugin runs members in sub-sessions under one captain.
- Notification plugins carry only the "ping Kim" half.
- `@240xu/dsh-message-ops` edits a session's message history; it is not agent messaging.
- I checked the market index on 2026-11-09. The index is large, so this is "none found",
  not "none exists".

## 4. Assumptions to verify before the design is accepted

These are unverified. Each one needs a small test. If one fails, the plugin idea loses its
main advantage and the fallback is the current files plus relay.

| # | Assumption | Test |
|---|---|---|
| A1 | A plugin tool runs in the DSH host process, so its own file writes are not limited by the calling session's sandbox. | From a `workspace-write` session, call a test plugin tool that writes one byte to a file outside that session's workspace. |
| A2 | A tool can see the calling session id (`exec.agent.id`), and the host can map it to the session's working directory. | Test tool returns the id and the mapped directory. |
| A3 | A plugin row can load an absolute-path JS file with no `node_modules`, as the Kagi plugin does. | Already true for the Kagi row. Reconfirm with a tool-registering module. |
| A4 | A tool error is reported to the model and does not stop the host. | Throw from the test tool. |

A1 is the one that matters. This design is a deliberate privilege escalation: every agent
on the host can call the tool. If A1 or A2 fails, v1 shrinks to read-only tools or is
dropped.

## 5. Plugin v1

### 5.1 Mechanism

- A dependency-free ESM file, loaded by absolute path from `~/.dsh/cordis.patch.yml`. This
  is the same pattern as `pkgs/dsh-web-search-kagi`.
- It exports `name`, `inject`, and `apply(ctx, config)`, and registers tools with
  `ctx.tools.register()`. A plain tool definition object is enough; `defineTool` is only a
  validation helper.
- Its own writes go through `node:fs`, in the host process. That is why it can cross the
  sandbox (assumption A1), and why the allowlist in 5.4 is the main control.

### 5.2 Caller identity and permissions

- The tool gets the caller from `exec.agent.id` (assumption A2). It derives the caller's
  workspace from that session's working directory.
- `inbox_send` stamps `:FROM:` from the caller workspace and session id. The caller cannot
  supply or spoof it.
- `inbox_archive` is allowed only when the caller's workspace is the inbox owner. No
  agent can close another workspace's requests.
- `inbox_list` and `inbox_get` are read-only and open to all four workspaces.
- If the caller cannot be identified, the tool fails closed: send and archive refuse, list
  and get still work.

### 5.3 Store

Decision: v1 keeps the visible files in each workspace root. It needs no migration and Kim
can read them in place. Moving the store to `~/.dsh/inboxes/` is a later option, not part
of v1.

### 5.4 Files and allowlist

The plugin writes only inside the four roots, and only these names:

- `<root>/inbox.org`
- `<root>/inbox_archived.md`
- `<root>/.inbox.lock` (created, used, and removed)
- `<root>/.inbox.tmp-<pid>-<random>` (atomic-write temp; renamed over the target)

Everything else is refused. Resolve each path with `realpath` and reject a result outside
the root, a symlink, or a `..` segment. The lock is taken with `O_EXCL`; a stale lock older
than 60 s is removed.

### 5.5 Tools

| Tool | Arguments | Behaviour |
|---|---|---|
| `inbox_send` | workspace, title, ask, proposed_fix, diff?, questions?, done_when, blocking? | Appends one block. Returns its id and path. |
| `inbox_list` | workspace | Returns open blocks: id, title, sender, age, first line, malformed flag. |
| `inbox_get` | workspace, id | Returns the whole block. |
| `inbox_archive` | workspace, id, outcome, what_changed, notes? | Moves the block verbatim to the archive, adds an outcome line, deletes it from the inbox. |

Rules:

- An unknown workspace is an error that lists the valid names.
- Block id: `<received-epoch-ms>-<first 8 hex of sha256(title + from + created)>`.
- Existing blocks without an id get a computed id at list time. `inbox_list` does not skip
  a malformed block; it returns the block with `malformed: true`, and `inbox_archive`
  still moves it.
- Caps: 64 KiB per block, 10 open requests per inbox, 1 MiB per inbox. A send that would
  exceed a cap fails; nothing is dropped.
- `inbox_archive` is the single commit point. A second archive of the same id returns
  "not found"; the caller must not redo the work.
- The tool never runs commands, touches services, or uses the network.

### 5.6 Block format

```org
* Add the mail-window classifier to the systems-flake docs
:PROPERTIES:
:ID: 1794238201123-a1b2c3d4
:FROM: job search agent, session f8100090
:CREATED: 2026-11-09T14:30:00-05:00
:STATUS: open
:END:
** Ask
...
** Proposed fix
...
** Open questions
- ...
** Done when
...
```

The archive is markdown. Each entry has the metadata, an outcome line, and the original
block copied verbatim.

### 5.7 Failure modes

| Failure | Behaviour |
|---|---|
| Lock contention | retry once, then return an error |
| Archive write fails | keep the block in the inbox |
| Malformed block | list shows it, get returns it, archive moves it |
| Disk full | the send fails loudly; no partial block |
| Caller unknown | send and archive refuse |

### 5.8 Security

- The tool is a sandbox bypass. The allowlist in 5.4 and the owner-only archive rule are the
  controls. The code must be small and reviewed before it is enabled.
- The worst case must be "one of the eight content files changed by an agent's own tool
  call, plus its lock and temp siblings". It must never reach a service, a deploy, or
  another path.
- Requests must contain no secrets. The plugin cannot reliably detect them, and the archive
  keeps text verbatim. If a secret lands there, rotate it and delete the file.
- Request text is untrusted data. Agents must not follow instructions inside a request.

### 5.9 Loading and updates

- The row goes in `~/.dsh/cordis.patch.yml`, next to the Kagi row. The code is versioned in
  `systems-flake/pkgs/dsh-inbox`.
- A new or changed plugin needs a DSH restart unless HMR picks it up.
- A bundle (npm package installed by the plugin manager) is a later option if the file
  proves useful.

## 6. Auto-review

### 6.1 Levels

| Level | What runs | Who acts | Cost |
|---|---|---|---|
| L1 session-start check | the agent lists its inbox at the start of any session | the agent reports; Kim decides | one line in the agent MD, no plugin |
| L2 host notify | a host watch on the inbox files | nobody; Kim gets a ping | a small watcher |
| L3 scheduled triage | a DSH cron in the target session | the target agent accepts, rejects, or answers | a schedule per workspace |
| L4 auto-apply | the target agent applies accepted requests | the target agent, without Kim | high risk |

L1 is the cheapest useful form of "auto review". It needs no wake and no schedule: whenever
Kim opens that workspace, the agent reports open requests. Start there.

### 6.2 Scope

Phase 3 covers **grocery and OCD only**. Job search and systems-flake stay at L1 until Kim
opts in explicitly.

### 6.3 Wake mechanism for L3

- A DSH schedule is bound to one session. It is durable and can deliver into an idle
  session. Evidence: one test reminder delivered to an idle session 69 ms late on
  2026-11-09. That shows delivery at least once; it does not yet show survival across a DSH
  restart, or that a woken session has its tools.
- Who creates it: Kim, once per workspace, by asking that workspace's agent to create the
  schedule. The schedule records the session id it was created in.
- If that session is deleted or replaced, the schedule does not follow the new session. It
  must be recreated.
- Phase 3 gate: a wake test after a DSH restart, twice, with the agent accepting one
  request and rejecting one.

### 6.4 Trust policy

These are **proposed defaults**, not decisions. They live in the workspace's agent MD so
they are human-readable.

| Workspace | May accept alone | Must escalate to Kim |
|---|---|---|
| grocery | list, recipe, errand edits | any purchase, order, or spend |
| OCD | reference and note edits | any rewrite of the personal record |
| job search (manual until opted in) | notes, docs | mail sending, candidate state |
| systems-flake (manual until opted in) | comments, prepared patches | deploy, service changes |

### 6.5 Limits

- At most three requests per review. The rest stay open; they are not dropped.
- No auto-forwarding to a third workspace.
- No running another workspace's scripts, no deploys, no service commands, no network sends.
- Every outcome goes to `inbox_archived.md` and the session log.
- One short summary to Kim per day.
- Empty inbox: no message and no work.
- Opt-in per workspace; one switch stops it.
- Double processing: check the id and status before acting. The first successful archive
  wins; the second caller gets "not found".

## 7. Phasing

| Phase | Deliverable | Gate |
|---|---|---|
| 0 | files and prompt protocol (done) | manual use |
| 0.5 | assumption tests A1–A4 | all pass, or this design shrinks |
| 1 | plugin v1: send, list, get, archive | code review; one week of manual relay first |
| 2 | L1 session-start check in all four agent MDs | one week, no confusion |
| 3 | L3 scheduled triage for grocery and OCD | two weeks of L1; wake test passes; Kim's yes |
| 4 | L4 auto-apply | 20 handled requests, 0 incorrect acceptances, Kim's explicit yes |

## 8. Open questions

1. Are the proposed trust defaults in 6.4 right?
2. Is L1 (session-start check) enough for grocery and OCD, or is a schedule wanted?
3. Do requests need an expiry or a priority field?
4. Is a DSH restart acceptable for plugin updates?
5. Should the plugin take structured arguments only, or also accept a raw org block?
6. If A1 fails, is the relay-only fallback acceptable, or should we try a different host
   mechanism?

## 9. Risks

- The plugin is a privilege escalation. Small code, path allowlist, owner-only archive.
- DSH is a release candidate; the tool seams may change.
- Agent loops: A asks B, B asks A. Cap per review; no auto-forward.
- Request text is untrusted data.
- A silent auto-accept mistake is the costly failure. Keep L3 conservative; gate L4 on data.
- The inbox files are gitignored and written atomically, so they do not enter commits.

## 10. References

- `pkgs/dsh-web-search-kagi/index.js` — host-local plugin precedent.
- `~/.dsh/cordis.patch.yml` — plugin rows.
- `docs/capability-seams.md` in the DSH checkout — service and seam list.
- The Team direct-inbox guide shipped with this checkout — background only; it covers
  same-session teammates, not cross-workspace mail.
- Market index URL in the header (checked 2026-11-09).
- The four workspace agent MDs, plus each `inbox.org` and `inbox_archived.md`.
