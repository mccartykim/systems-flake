# PRD — a boring self-care agent (the simple lifecoach)

**Status:** design, for a coding agent. Nothing here is built.
**Author:** written 2026-10-09 by the `jobcoach` Hermes profile, on Kim's request.
**Supersedes the *scope* of** `hosts/rich-evans/lifecoach-organism.nix` — not the service, which stays
running (see §6).

---

## 1. The ask, in her words

> *"a simpler lifecoach focused on selfcare routine without the roleplay and barking, just a regular,
> boring agent that works with home assistant."*
>
> *"i've been ignoring the current lifecoach and org-crm messages… they're not especially helpful since
> i have the speakers unplugged. don't disable them but consider the blast area."*
>
> *"i think it may make sense to use clef if it runs fast on historian.nebula's ollama as a vision
> decision model but that'd need benchmarking."*

**Success is:** a self-care routine that holds — medication, sleep/wake, meals, the weekly NYS
certification — delivered as a *quiet, useful* signal she does not resent. Not a companion. Not a
nudge engine. A boring agent that knows the routine and says one thing when it matters.

**Non-goals (explicit):**
- Not a therapist, not a crisis service, not a companion. (Her own `wellbeing.org`: *"agent is a
  partner, not a therapist."*)
- Not a general life coach. Not a task manager. Not a replacement for `job-search.org`.
- **No roleplay.** No characters, no names, no themed layers. The 40k officer fleet is gone and stays gone.
- No scores, streaks, tallies, or fractions. Ever.
- Not a voice/TTS feature. The speakers are unplugged and the TTS *"just made me feel worse."*

---

## 2. Why the current one doesn't work — verified, not assumed

Read from config; running-state claims were confirmed by SSH where marked.

### 2.1 It is chatty by construction

| Unit | Cadence (from `systemctl list-timers` on rich-evans, 2026-10-09) |
|---|---|
| `lifecoach-scheduler.timer` | **every 60 s** |
| `lifecoach-watchdog.timer` | 5 min |
| `lifecoach-heartbeat.timer` | 30 min |
| `vacuum-scheduler.timer` | every 60 s |
| `vacuum-watchdog.timer` | 5 min |
| `vacuum-heartbeat.timer` | 30 min |
| `org-agent-emacs-watchdog.timer` | 5 min |

Six non-system timers, two of them firing **every minute**, on a 4-core/15 GB box
(`rich-evans`: 4 × nproc, 15 GB RAM, ADATA SU670). The heartbeat alone is documented at
**~$0.04/cycle × 30 min ≈ $1.92/day**.

### 2.2 Four bots share one Discord surface — and a bridge mirrors all of it into Matrix

Posting to Discord today: `lifecoach-discord-bot`, `vacuum-discord-bot`, `discord-org-crm`, and
`email-digest`. On historian, `services.mautrix-discord`
(`hosts/historian/matrix.nix:42`) mirrors every Discord message into Matrix (homeserver
`services.matrix-tuwunel`, `:31`). **Every notification therefore arrives twice, and she gets pinged
on her own posts.** Her words: *"yuck."* A separate task already exists to kill that bridge.

### 2.3 The outputs are not attached to anything she can act on

The `Active deadlines & todos` index in `job-search.org` is largely **blocked on other people** —
the attorney, the realtor, a recruiter. Her own `tools/nudge-policy.org` names this: *nudging a
blocked item is guilt with no possible response.* A routine that surfaces blocked items is
generating pressure, not help.

---

## 3. Hard constraints

1. **`nix shell` / `nix develop` / flake only.** Never install a program. Hermes' own prebuilt
   binaries (`agent-browser`, its downloaded Chromium) cannot exec on NixOS — `/lib64/ld-linux-x86-64.so.2`
   is a `stub-ld` shim. Do not add more of the same.
2. **Reuse her existing secrets via agenix.** `secrets/secrets.nix`; `ha-life-coach-token.age` is
   shared and still live.
3. **Plain speech to her.** No inflation. Short. One decision at a time.
4. **Her clock is flipped.** She wakes mid-afternoon and is awake overnight. Any delivery window
   must be set by her; a 09:00 message is worse than none.
5. **Nothing may speak without saying what it is.** No sound without warning. `notify-send` is not
   installed; `dbus-send` against `org.freedesktop.Notifications` works on her session bus.
6. **Removable in one command, with no important state inside it.**

---

## 4. Design

### 4.1 Recommendation: build it on Hermes, not as another bespoke daemon

**Hermes is not in nixpkgs.** It ships its own flake. The source checkout lives at
`~/.hermes/hermes-agent` (git clone of `NousResearch/hermes-agent` @ `46d7718a`, v0.0.0 2026.9.24) and
contains:

```
nix/nixosModules.nix        -> flake.nixosModules.default  =>  services.hermes-agent
nix/homeManagerModules.nix  -> the same options, for home-manager
nix/packages.nix            -> the package (uv2nix)
nix/moduleCommon.nix        -> shared options + config.yaml/.env renderers
```

Wiring it in is a normal flake-input job:

```nix
# flake.nix
inputs.hermes-agent.url = "github:NousResearch/hermes-agent";
```

```nix
# hosts/historian/hermes.nix
{ inputs, ... }: {
  imports = [ inputs.hermes-agent.nixosModules.default ];
  services.hermes-agent = {
    enable = true;
    stateDir = "/var/lib/hermes";
    environmentFiles = [ config.age.secrets.hermes-env.path ];
    # settings.model.default = …
  };
}
```

**Why this instead of a new `kimb.selfcare` Python module alongside `sre-agent`:** the messaging
gateway, per-chat sessions, the cron scheduler, the memory/skills layer and the approval prompts
already exist there and are maintained by someone else. The officer fleet died of *bespoke
accumulated code*; this design should add as little of that as possible.

**Deploy on `historian`** (24 cores, 57 GB) — **not** `rich-evans` (4 cores, 15 GB), which is
already running the emacs daemon, syncthing, both Discord bots and the camera stack.

### 4.2 Delivery channel — decide this first, it shapes everything else

Hermes supports, among others: **ntfy, Discord, Telegram, Signal, Email, Matrix, Home Assistant,
SMS, Slack, Mattermost.** Two properties matter more than the rest:

- **Intentional silence is built in.** If the final response is exactly `[SILENT]` / `NO_REPLY`,
  the gateway suppresses delivery entirely. *"Silent when there is nothing worth saying"* stops
  being a behavioural rule and becomes a mechanism.
- **The gateway runs the cron scheduler** (60 s tick), and installs as a service
  (`hermes gateway install --system`).

| Channel | Setup cost | Why / why not |
|---|---|---|
| **ntfy** | **lowest** | Self-hostable, no bot account, no server, push to a phone app. It is a *notification* channel, not a chat — closest to "tasteful notification popups" and it cannot become a second inbox. **Recommended for the nudge path.** |
| **Discord** | low (~10 min) | She already runs bots here. `hermes gateway setup` → Discord creates the app, checks the token, flags a missing **Message Content Intent**, prints an invite link and allowlists her as owner. **The #1 failure: if Message Content Intent is off in the Developer Portal, Discord *refuses the connection* and the bot never comes online.** Server Members Intent is also required. But Discord is where the current noise lives — put *conversation* here, not alerts. |
| **Telegram** | low | Fullest feature matrix (voice, images, files, threads, reactions, typing, streaming). Clean and reliable if she wants a chat surface without Discord. |
| **Email** | medium | Durable, no push, no bot account. Good as a weekly digest, bad as a nudge. |
| **Signal** | medium | Supported (images/files/typing); no voice. Needs a linked device. |
| **Home Assistant** | — | Hermes lists Home Assistant as a messaging platform. See §4.4 — HA is better used as the *sensor/actuator*, not the channel. |

**Recommendation:** **ntfy for nudges, Discord for talking to it.** And do not configure both to
carry the same message — one surface per message class, or this becomes the bridge problem again.

### 4.3 The judgment layer — do NOT start with clef

**What clef is.** Cloudflare's family of *decision* models, open weights, wire-compatible with the
Jev/SystemOne APIs. In Ollama as `clef` (27B, ~18 GB) and `clef-flash` (9B, ~11 GB). **It is not a
chat model** — you POST a state plus a schema of typed questions to `/v1/systemone` and get a
probability per allowed option. Published: Clef-Flash 93.11 vs Jev 88.19 on API-Bank.

**Verified current state of the hosts:**

| Host | Ollama | Models | Has a vision model? | Has clef? |
|---|---|---|---|---|
| `historian.nebula` | 0.34.3 | `gemma4:e4b`, `smollm2:135m`, `kimi-k3:cloud`, `qwen3.5:cloud`, `kimi-k2.7-code:cloud`, `qwen3.5:397b-cloud` | **no** | **no** |
| `total-eclipse.nebula` | — | 20 incl. `minicpm-v4.6:latest`, `glm-ocr:latest`, `gemma4:e2b/e4b` | yes | no |

So the premise *"clef on historian's ollama"* requires pulling 11–18 GB onto a box that currently
has no vision model at all, and **its GPU is not verified** (`lspci` is not installed on her hosts).

**The finding that matters most, and it is not about speed:** the official Clef release ships a
separate **joint schema head** that scores the allowed options. A widely-circulated local test of
`bartowski/Cloudflare_clef-flash-GGUF:Q4_K_M` under Ollama found **427 backbone tensors and zero
schema/head matches** — the local answers were 21–30 *generated tokens parsed as JSON*, not native
decision probabilities. On an RTX 4060 8 GB it did run: ~1.4–2.0 s warm, 87 % GPU. **⇒ "clef in
Ollama" and "clef via API" are different mechanisms, and the local one is not the calibrated one.**
That is exactly the trap `tools/why-jev-is-still-in-play.md` warns about: *"check the runtime, because
the model name alone does not tell you which mechanism is running."*

**And the prior decision already answered this.** `tools/why-jev-is-still-in-play.md` and
`tools/nudge-policy.org` reached: *mechanical rules implement all of D1–D9; a classifier only helps
for questions with no crisp predicate.* For a **self-care routine**, the questions are crisp:

- Is it the window? — arithmetic.
- Has she acknowledged today's meds? — a flag.
- Is she awake? — a signal, not a judgment.
- Is this item blocked on someone else? — a lookup.

**⇒ Recommendation: rules only in v1. Do not pull clef. Do not pull any vision model.** Add a
classifier only if the *exception count* grows — that is the honest trigger, and it is her own
conclusion, not a new opinion.

**If and when it is wanted, benchmark before adopting.** Suggested protocol (nothing here has been
run):

```sh
# on historian — never on rich-evans
ssh historian.nebula 'docker stats --no-stream 2>/dev/null; nvidia-smi 2>/dev/null || echo "no GPU"'
ssh historian.nebula 'free -g | head -2'
# pull only after the box is known adequate
ssh historian.nebula 'ollama pull clef-flash'
# prove which mechanism is running: does the GGUF carry the joint head?
ssh historian.nebula 'ollama show clef-flash --modelfile | head -40'
# then TIME it against the rules baseline on recorded history
time curl -s http://historian.nebula:11434/v1/systemone -d @bench-state.json | jq .
```

**Acceptance gate for clef:** it must *measurably* collapse exceptions versus the rule set, on
replayed history, and the local file must be shown to carry the schema head. Otherwise it is a
second system to validate.

### 4.4 Home Assistant is the sensor layer, not the chat layer

Already wired: `haUrl = "http://10.100.0.10:8123"`, `haTokenFile = config.age.secrets.ha-life-coach-token.path`.
`home-assistant.service` runs on historian. Use HA for:

- **Read:** is she in bed / awake / home / phone-charging. This replaces "vision" for the one
  question that matters (is she asleep) with a *signal* rather than a camera — cheaper, more
  reliable, and it does not require looking at her.
- **Act:** the existing button/LED path. `lifecoach-button-monitor` + the `bed0up → desk_task_3`
  binding are the physical interface; **do not strand them.**

Cameras (`127.0.0.1:8554/cam0/cam1` on rich-evans) are **out of scope for v1**. They are the
expensive, privacy-loaded path, and the `D6` vision dependency is still an open question in the
current design.

### 4.5 The stand-down and silence contract

These are non-negotiable and must be structural, not prompt-level:

1. **A plain `no-nudge` file is checked before anything else runs.** If present, exit silently. No
   model gets a vote, no probability may override it.
2. **`[SILENT]` / `NO_REPLY`** as the only response when nothing is worth saying. No "nothing to
   report" filler — that is how a useful channel becomes noise.
3. **One recipient: her.** Hardcoded, enforced in code, refusing on mismatch rather than warning.
   Drafts to other people are files that never touch the send path.
4. **Read-only with respect to every `.org` file.** A daemon that silently rewrites the source of
   truth is how the file stops being trustworthy.
5. **Never nudge a blocked item.** If the next action is someone else's, it generates nothing.
6. **Delivery window set by her, full darkness outside it.** Nothing during sleep.
7. **Hard cap per day**, and an **explicit keep-or-kill date**.
8. **No tallies, streaks, or fractions.** No "day 4 of 7."
9. **Loud failure, quiet success.** A broken heartbeat should surface once, plainly — not retry loudly.

### 4.6 What the routine actually covers

Keep it to what a self-care routine needs, and nothing else:

- **Meds** — the one exception that may persist. *"Persist without a tally"* (her own policy).
  Today's reality: Prozac collected; Vyvanse is a C-II that depends on the prescriber, not the
  pharmacy.
- **Sleep/wake** — from HA, not a camera.
- **Meals / water** — low-stakes, and probably a single daily anchor rather than three pings.
- **The one hard external clock** — the NYS weekly certification (Sun–Sat, 3 work-search
  activities/week). A missed week is a lost week, with repayment and penalties attached. This is
  the single item most worth a nudge, and it is *not* blocked on anyone.

Everything else in `job-search.org` is either a project or is blocked on a third party. Leave it.

---

## 5. Phased implementation

| Phase | Deliverable | Blast radius | Gate |
|---|---|---|---|
| **0** | Add the `hermes-agent` flake input; enable `services.hermes-agent` on historian doing **nothing** (no cron, no platforms). Confirm it starts, `hermes doctor` is clean, state is at `/var/lib/hermes`. | additive, one line to disable | nothing |
| **1** | Wire **one** channel — ntfy — and prove a message arrives, and prove `[SILENT]` suppresses one. | additive | §4.2 decision |
| **2** | The **`no-nudge` file + window + cap** wrapper, as a script-only cron job. Prove it exits silently when the file exists. | additive | nothing |
| **3** | **HA read path** — one question (*is she in bed*), one value, logged. No action. | read-only | HA token reuse confirmed |
| **4** | The **meds flag** — the one persistent item, no tally. | additive | her approval of exact wording |
| **5** | Run it **alongside** the existing lifecoach for two weeks. Compare: messages sent, messages she acted on, messages she ignored. | none — both running | §7 keep-or-kill date |
| **6** | **Only then** decide what, if anything, to switch off. | — | her call, explicitly |

**Do not** renumber your way to phase 6. Phases 0–2 are the whole win; 3–5 are where the risk lives.

---

## 6. Blast radius — what must NOT be touched

Verified by reading config, and by SSH to the running hosts on 2026-10-09.

| Thing | Why it must survive |
|---|---|
| `services.org-life-coach` | Its **python daemon is `mkForce`-disabled**, but it still provides the **emacs daemon** at `/var/lib/life-coach-agent/emacs/org-agent` — `lifecoach-organism.nix` points `orgAgentSocket` at it, and other things call it. **Killing this module breaks org task reads.** |
| `services.lifecoach-organism` | Still enabled and running on rich-evans. Leave it. |
| `services.vacuum-organism` | Running (`vacuum-discord-bot`). `hosts/rich-evans/vacuum-organism.nix` puts `life-coach` in the `vacuum-organism` group so the `dispatch-robot` wrapper can write `dispatch.org`. |
| `org-crm` | Runs on historian (`org-crm.service`, `discord-org-crm.service`). Independent of the officers. |
| `email-digest` | On historian; **its two-service split (index vs digest) is load-bearing** — a full `mu index` takes ~50 min on spinning rust, far past any sane timeout. |
| `lifecoach-button-monitor` + `bed0up` binding | The physical interface. |
| `/var/lib/*` state dirs | `lifecoach-organism`, `life-coach-agent`, `mautrix-discord`. Disable, don't delete. |
| Tuwunel signing keys | `/var/lib/private/tuwunel` — **the federation identity of `kimb.dev`. Do not rotate.** |
| `matrix-life-coach-token.age` | Now effectively unused (the live lifecoach sets `matrixBotTokenFile = lib.mkForce null`), but leave it sealed. |
| Dangling officer SSH key | Authorises `ssh-ed25519 AAAA…IJkCorkwI7RWuRNFg241GpMSj2ZE2rxgF+IPoPF7E8wN` in `hosts/historian/kdeconnect-sms.nix` and `hosts/total-eclipse/sms-history.nix`. Left deliberately; **remove if the key is ever re-issued.** `sms-history` itself is a ready-made read-only "did anyone text me" tool if wanted. |

---

## 7. Acceptance criteria

- [ ] `services.hermes-agent` evaluates for historian and starts clean; `nix flake check` passes.
- [ ] A message arrives on exactly one channel; a `[SILENT]` reply arrives on none.
- [ ] With `no-nudge` present, the scheduled run produces **no output and no error**.
- [ ] No `.org` file is ever written by the scheduled path (prove by hashing the tree before/after).
- [ ] The run finishes well inside Hermes cron's **3-minute hard interrupt** — long work stays a
      systemd timer (the `email-digest` index/digest split is the precedent).
- [ ] Nothing is nudged whose next action belongs to another person.
- [ ] Message count per day ≤ cap; quiet hours produce zero messages.
- [ ] `ss -ltnp` shows no new listening port beyond the gateway's own.
- [ ] A keep-or-kill date is recorded, and removing it is one command.

---

## 8. Open questions — hers to answer, not mine to assume

1. **Which channel?** ntfy / Discord / Telegram / Signal / email. (Recommended: ntfy for nudges.)
2. **What window?** Set by her. Given the flipped clock this matters more than any other parameter.
3. **Hard cap — how many times a day may it speak at all?**
4. **Keep-or-kill date?**
5. **Does it replace part of the current lifecoach, or sit alongside it?** Decide on purpose.
6. **Meds wording** — the one item that may persist. She should approve the exact sentence.
7. **Is `sms-history` wanted** for "did anyone text me"?

---

## 9. Honest risks

| Risk | Consequence | Mitigation |
|---|---|---|
| **It becomes the officers again** | a chatty fleet she mutes | §4.5 stand-down + cap + kill date; phases 0–2 only |
| Alarm fatigue | she ignores it, and then ignores the one that mattered | window, cap, silence token, never-a-blocked-item |
| **clef is the wrong mechanism locally** | a probabilistic layer she cannot validate | §4.3 — rules first; benchmark and require the schema head |
| Vision creep | privacy + the `D6` dependency | cameras out of scope in v1; HA signals instead |
| Bespoke code accumulates | the actual failure of the last two systems | build on Hermes, add as little custom Nix as possible |
| A missed NYS week | lost benefits + repayment + penalty | this is the one item that earns a nudge |

---

## 10. One-paragraph summary

Replace the officer-era lifecoach with a Hermes agent on `historian` — not a new bespoke daemon,
because the gateway, sessions, cron, memory and silence token already exist there and are
maintained by someone else. Deliver over **ntfy** (a notification channel, not a chat), keep
**Discord** for conversation, and do **not** configure both to carry the same message. Get the
routine from **Home Assistant signals**, not cameras. **Skip clef in v1** — for a self-care routine
the questions have crisp predicates, her own notes already concluded that rules suffice, the local
GGUF loses the calibrated joint-schema head, and historian has no clef and no vision model today.
Carry the stand-down file, the silence token, one recipient, read-only org files and a keep-or-kill
date from the first line. Run it alongside the old one for two weeks before switching anything off,
and never touch `org-life-coach`'s emacs daemon, the button/LED path, or Tuwunel's signing keys.
