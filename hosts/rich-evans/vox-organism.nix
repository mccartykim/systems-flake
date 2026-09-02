# Host enablement for the Phase-2 vox-organism comms bridge (the Astropath) on
# rich-evans. Replaces the Phase-1 placeholder services.voidmaster-vox-bridge
# (disabled in voidmaster-vox-bridge.nix — one-line rollback).
#
# The module ships from the 40k_bridge source as deploy/vox-organism.nix
# (imported in flake-modules/nixos-configurations.nix; takes bridgeCrewSrc as
# a module arg, threaded via specialArgs). This file is config-only.
#
# Phase 2 is Matrix-first: the daemon is a /sync polling client over loopback
# (127.0.0.1:6167, same host as Tuwunel), reusing the existing @vox-bridge:kimb.dev
# access token — NO @astropath mint, NO registration flip. The .age file is NOT
# re-encrypted; only the Nix `owner` attr flips from voidmaster-organism to
# vox-organism so the daemon (uid 998) can read its token.
{
  config,
  lib,
  pkgs,
  inputs,
  organism,
  bridgeCrewSrc,
  ...
}: let
  # The bridge-crew roster — the single source of truth for officer rooms +
  # identity (deploy/roster.nix in the 40k_bridge source). The daemon's rooms
  # (every officer dialogue room incl. the cross-host Navigator + the
  # vox-bridge vigil room) are DERIVED from it, not hand-listed, so adding an
  # officer is one roster entry, not an edit here. The structured bus
  # (#bridge-events) is appended — it is not an officer.
  roster = import "${bridgeCrewSrc}/deploy/roster.nix" {inherit lib;};
  # The Chirurgeon's household tools (speak / compel-spirit / ha-get-state /
  # build-view) live in the chirurgeon_organism package bin; medicae-infer
  # dispatches them as bare names on PATH. build-view cold-starts org-agent's
  # emacs (binary + init.el) — no daemon, no socket. Both are mirrored onto
  # the daemon below.
  org-agent-emacs = inputs.org-agent.packages.${pkgs.system}.emacs;
  org-agent-init = "${inputs.org-agent}/elisp/init.el";
  chirurgeon-pkg = inputs.bridge-crew.packages.${pkgs.system}."chirurgeon-organism";
  # The Interrogator's #+AGENT shell (interrogator-infer) lives in the
  # interrogator_organism package bin; organism resolves `#+AGENT:` as a bare
  # name on PATH, so the daemon must carry the package bin or the reactive
  # #interrogator cycle fails ~1ms in (command not found). interrogator-infer
  # is inference-only (no household tools / HA / TTS / build-view) so unlike the
  # Chirurgeon it needs NO env additions — only the package bin on PATH (mu is
  # already on the module's path; the email-digest group membership is roster-
  # derived). Mirrors the chirurgeon-pkg path addition for the #62 fix.
  interrogator-pkg = inputs.bridge-crew.packages.${pkgs.system}."interrogator-organism";
  # The Remembrancer's #+AGENT shell (remembrancer-infer) lives in the
  # remembrancer_organism package bin; organism resolves `#+AGENT:` as a bare
  # name on PATH, so the daemon must carry the package bin or the reactive
  # #remembrancer cycle fails ~1ms in (command not found) — same gap the
  # interrogator-pkg addition closed. remembrancer-infer is inference-only
  # (read_file / officer_view are read-only bash tools already on PATH); it
  # needs NO env additions, only the package bin on PATH. Mirrors the
  # interrogator-pkg path addition.
  remembrancer-pkg = inputs.bridge-crew.packages.${pkgs.system}."remembrancer-organism";
  # Savant Quine — read-only reference librarian + print. savant-infer is
  # the #+AGENT shell (interrogator-infer fork); organism resolves it as a
  # bare name on PATH, so the daemon must carry the package bin or the
  # reactive #savant cycle fails ~1ms in (command not found) — same gap the
  # interrogator-pkg addition closed. The bare print-file tool calls `lp`
  # (cups) + `file`/`pdftotext` (poppler-utils) as bare names, so those go on
  # the daemon PATH below too. NO env additions (savant-infer reads OFFICER_STATE
  # for logging like the Interrogator; print-file's printer defaults are baked).
  savant-pkg = inputs.bridge-crew.packages.${pkgs.system}."savant-organism";
  # Choirmaster Cassiel — on-demand music. choirmaster-infer is the #+AGENT
  # shell (medicae-infer fork); organism resolves it as a bare name on PATH.
  # Every choirmaster bin is wrapped with its runtime deps (mpc, python
  # w/ pychromecast+requests, CHOIRMASTER_LIB_PARENT) so the daemon needs ONLY
  # the package bin on PATH — cast-stream auto-detects the LAN IP + defaults
  # port 8666 + the Nest hub device. CHOIRMASTER_STATE is mirrored for clean
  # logging (parity with CHIRURGEON_STATE); MPD_HOST/MPD_HTTP_PORT/TTS_DEVICE
  # all have working defaults.
  choirmaster-pkg = inputs.bridge-crew.packages.${pkgs.system}."choirmaster-organism";
  # Factor Voss — finance axis. factor-infer is the #+AGENT shell (medicae-
  # infer fork); organism resolves it as a bare name on PATH. The package
  # wrap deliberately EXCLUDES hledger/git/poppler (they reach runtime via
  # the module's servicePath — but the daemon path doesn't use the module's
  # servicePath), so hledger/hledger-utils/git MUST go on the daemon PATH
  # below for the reactive #factor cycle to read/write the real ledger.
  # FACTOR_STATE/FACTOR_LEDGER/FACTOR_CSV_DIR are ESSENTIAL env (without
  # them the ledger defaults to /tmp/factor/ledger.journal + the finance
  # duty breaks); mirrored below.
  factor-pkg = inputs.bridge-crew.packages.${pkgs.system}."factor-organism";
in {
  services.vox-organism = {
    enable = true;
    # @vox-bridge:kimb.dev access token — REUSED from Phase 1 (agenix secret;
    # minted via a transient allow_registration flip — see deploy/GO_NOGO.md §3
    # + the matrix-token-mint-requires-registration-flip memory). Only the
    # owner flips (below); the .age file is not re-encrypted.
    matrixBotTokenFile = config.age.secrets.matrix-vox-bridge-token.path;
    # nixpkgs has no `organism` package; the binary ships from the organism
    # flake input. The `organism` specialArg is threaded via rich-evans's
    # extraSpecialArgs in nixos-configurations.nix.
    organicBin = "${organism.packages.x86_64-linux.default}/bin/organic";
    # The rooms the daemon joins at startup (officer dialogue rooms + the
    # vox-bridge vigil room + the bridge-events structured bus). The daemon
    # auto-creates any that do not yet exist + invites @kimb:kimb.dev. The
    # Chirurgeon (#62) joins the crew as the 5th officer dialogue room; the
    # Navigator (#49) joins as the 6th — the CROSS-HOST officer (hosted on
    # total-eclipse, SSH-dispatched by the daemon via the routing table's host
    # column; see deploy/vox-organism.py:_invoke_organic_remote).
    # Roster-DERIVED (deploy/roster.nix): every officer's dialogue room, in
    # roster order (incl. the cross-host Navigator — the daemon routes
    # #navigator via SSH, so it joins the room locally) + the vox-bridge
    # vigil room (the Astropath's own #vox-bridge). The #bridge-events
    # structured bus is appended; it is not an officer. Adding an officer =
    # one roster entry, not an edit here.
    rooms = roster.rooms ++ ["#bridge-events:kimb.dev"];
    # Authoring hop: the daemon SSHes to this host (bridge-scribe on historian,
    # a forced-command servitor — see hosts/historian/bridge-scribe.nix) to
    # materialize an officer's `author` request (clone -> commit on
    # proposed/<slug> -> push). rich-evans is an antique mini PC that must not
    # run builds or grow clones, so the scratch clone + git push happen on
    # historian. Fleet-internal, over Nebula.
    #
    # The EXPLICIT `bridge-scribe@` user prefix is load-bearing: ssh defaults to
    # the LOCAL user (vox-organism) when no user@ is given, but vox-organism does
    # NOT exist on historian + the fleet key's forced command is registered ONLY
    # on bridge-scribe (hosts/historian/bridge-scribe.nix). Without the prefix
    # the hop ssh'es as vox-organism@historian -> no-such-user -> the #60
    # authoring loop fails every time (verified: getent passwd vox-organism is
    # absent on historian; authorized_keys.d/vox-organism absent; the materialize
    # forced command lives only in authorized_keys.d/bridge-scribe). Mirrors the
    # Navigator cross-hop's navigator-organism@<host>.nebula target.
    historianHost = "bridge-scribe@historian.nebula";
    # The fleet-internal ssh key (agenix below, owned by vox-organism) the
    # daemon uses for that hop. The per-repo GitHub deploy keys live ONLY on
    # historian (agenix, owned by bridge-scribe) — this daemon never sees them.
    fleetSshKeyFile = config.age.secrets.bridge-fleet-ssh-key.path;
  };

  # Flip the token owner from voidmaster-organism (Phase 1) to vox-organism
  # (Phase 2). The age-encrypted file (../../secrets/matrix-vox-bridge-token.age)
  # is UNCHANGED — only the decrypted-file owner changes so the daemon (uid
  # 998) can read it. Rollback: set owner back to "voidmaster-organism".
  age.secrets.matrix-vox-bridge-token = {
    file = ../../secrets/matrix-vox-bridge-token.age;
    owner = "vox-organism";
    mode = "0400";
  };

  # Vacuum pattern (the fleet's proven token-reuse shape, mirroring
  # ha-chirurgeon-token in life-coach.nix): the SAME .age file decrypted a
  # SECOND time to a new runtime path owned by chirurgeon-organism (0400), so
  # the Chirurgeon's matrix-page tool can read the @vox-bridge token WITHOUT
  # re-encrypting the secret or loosening the daemon's own 0400 copy. No
  # secrets.nix change (the .age is already encrypted to hostKeys.rich-evans +
  # bootstrap); no Matrix registration flip (the @vox-bridge account already
  # exists). This is the linchpin of the 2026-07-30 outage fix: gives the
  # Chirurgeon heartbeat a Matrix egress so med nudges reach the one durable
  # channel instead of dying with the HA/Cast/phone stack.
  age.secrets.matrix-chirurgeon-token = {
    file = ../../secrets/matrix-vox-bridge-token.age;
    owner = "chirurgeon-organism";
    mode = "0400";
  };

  # Fleet-internal ssh key (rich-evans -> historian) the vox-organism daemon
  # uses to reach the bridge-scribe forced-command servitor and materialize an
  # officer's `author` request. Owner is vox-organism (the daemon reads it);
  # mode 0400 (private key). This is NOT a GitHub key — it never touches github;
  # it only authenticates the in-fleet hop to the scribe. Private half encrypted
  # to rich-evans + bootstrap in secrets/bridge-fleet-ssh-key.age.
  age.secrets.bridge-fleet-ssh-key = {
    file = ../../secrets/bridge-fleet-ssh-key.age;
    owner = "vox-organism";
    mode = "0400";
  };

  # ------------------------------------------------------------------
  # #62 fix — let the daemon run the Chirurgeon's CONVERSATION cycle.
  #
  # The daemon runs every routed officer's `organic` cycle AS ITS OWN USER
  # (vox-organism), not as the officer. officer-infer officers (Void-Master,
  # Factotum, Confessor, Explorator, Astropath) emit #+NOOP every cycle — no
  # org-merge, no household tools — so they run fine as vox-organism with the
  # daemon's minimal inherited env (OLLAMA_* + ORG_AGENT_LLM_PROVIDER from
  # voidmaster-heartbeat via officerEnv). They never noticed the gap.
  #
  # medicae-infer (the Chirurgeon) is different: it MERGES (realtime * Regimen
  # edit needs a group-writable stateDir for the lockfile — fixed in the
  # chirurgeon_organism module's homeMode 0770) AND dispatches household tools
  # that need the Chirurgeon's env: the HA auspex (ha-get-state), the calendar
  # task view (build-view → org-agent emacs socket), and TTS (speak). Without
  # these, the context blocks hydrate empty, the model sees nothing to tend,
  # goes quiet (#+NOOP + reply=null), and the room sees the silent-sweep
  # placeholder instead of a reply.
  #
  # Fix: mirror the Chirurgeon's proven `cycleEnv` (chirurgeon_organism/nixos/
  # module.nix L88-119 — the SAME env the working chirurgeon-heartbeat uses)
  # into the daemon's service environment + add the chirurgeon package bin to
  # the daemon's PATH. build-view cold-starts the org-agent emacs via the
  # absolute $ORG_AGENT_EMACS the env pins (NO emacs on the daemon PATH, NO
  # daemon, NO socket — that 0700-socket path was EACCES for non-owners,
  # #82/#83). The daemon's _clean_env_for_organic strips only MATRIX_* (and
  # overrides OFFICER_STATE=VOX_STATE — harmless: medicae-infer reads the
  # officer-specific CHIRURGEON_STATE, not OFFICER_STATE), so HA_TOKEN_FILE /
  # HA_URL / ORG_AGENT_* / TTS_* / CHIRURGEON_STATE pass straight through to
  # the organic child. Inert for the officer-infer officers — they don't read
  # these vars.
  #
  # Least-privilege: the daemon gets its OWN HA token (ha-vox-organism-token,
  # vacuum pattern — one .age decrypted for a 4th user, owner vox-organism,
  # mode 0400, NO agenix re-encryption) so the Chirurgeon's 0400 token is NOT
  # widened to a group. vox-organism joins life-coach to traverse the 0750
  # org-agent emacs socket dir (same as the Chirurgeon + Confessor).
  #
  # Refactor note: this couples the daemon to the Chirurgeon's env + a 4th HA
  # token. Acceptable while the Chirurgeon is the only medicae-infer officer.
  # When a 2nd household officer appears, lift to a sudo-per-officer invoke
  # (daemon runs `sudo -u <officer> <officer-invoke>` so each officer's context
  # is self-contained and the daemon carries no officer envs/secrets).
  # ------------------------------------------------------------------
  age.secrets.ha-vox-organism-token = {
    file = ../../secrets/ha-life-coach-token.age;
    owner = "vox-organism";
    mode = "0400";
  };
  users.users.vox-organism.extraGroups = ["life-coach"];
  systemd.services.vox-organism.environment = {
    # medicae-infer error-log dir (officer-specific, so the daemon's
    # OFFICER_STATE=VOX_STATE override doesn't collide).
    CHIRURGEON_STATE = "/var/lib/chirurgeon-organism";
    # HA auspex (ha-get-state) + compel-spirit.
    HA_URL = "http://127.0.0.1:8123";
    HA_TOKEN_FILE = config.age.secrets.ha-vox-organism-token.path;
    # Regimen view — build-view cold-starts `emacs --batch` (NO daemon, NO
    # socket; sidesteps the 0700-socket-dir rule that broke the old
    # emacsclient path for non-owners, #82/#83). The daemon (in the life-coach
    # group) reads the 0644 regimen file under /var/lib/life-coach-agent.
    ORG_AGENT_EMACS = "${org-agent-emacs}/bin/emacs";
    ORG_AGENT_INIT = org-agent-init;
    ORG_AGENT_FILE = "/var/lib/life-coach-agent/agent.org";
    # speak / lib/tts.py (rung-2 smart-speaker vox).
    TTS_SERVER = "http://total-eclipse.nebula:8091";
    TTS_VOICE = "jet2";
    TTS_DEVICE = "Kim's nest hub";
    # Choirmaster error-log dir (officer-specific, parity with CHIRURGEON_STATE
    # above). choirmaster-infer logs to CHOIRMASTER_STATE (NOT OFFICER_STATE);
    # the daemon (in the choirmaster-organism group) can write here. The music
    # tools (cast-stream/play/mpd-status) carry their own env via the package
    # wrap (CHOIRMASTER_LIB_PARENT) + sensible defaults (MPD_HOST auto-LAN-IP,
    # MPD_HTTP_PORT 8666, TTS_DEVICE "Kim's nest hub") — no extra env needed.
    CHOIRMASTER_STATE = "/var/lib/choirmaster-organism";
    # Factor finance-axis env (ESSENTIAL — factor-infer + the hledger tools
    # read these, NOT OFFICER_STATE). Without FACTOR_LEDGER the ledger
    # defaults to /tmp/factor/ledger.journal + the reactive #factor cycle
    # reads/writes a throwaway. The daemon (in the factor-organism group) can
    # write the ledger + the git-versioned .git ledger-commit manages. CSV
    # dir is the future scraper drop (empty at MVP).
    FACTOR_STATE = "/var/lib/factor-organism";
    FACTOR_LEDGER = "/var/lib/factor-organism/ledger.journal";
    FACTOR_CSV_DIR = "/var/lib/factor-organism/csv";
    # matrix-history allowlist (Summarizer leg-a, grafted into interrogator-
    # infer): comma-separated room IDs the daemon may backfill via /messages
    # when the Interrogator/Summarizer asks "summarize #<room>". DERIVED from
    # the roster (deploy/roster.nix voxHistoryRooms — every officer dialogue
    # room, EXCLUDING #bridge-events). Fail-closed per room. The NON-MATRIX_
    # name passes _clean_env_for_organic (see bin/matrix-history).
    VOX_HISTORY_ROOMS = lib.concatStringsSep "," roster.voxHistoryRooms;
  };
  # medicae-infer dispatches speak/compel-spirit/ha-get-state/build-view/log-
  # observation as bare names → they must be on the daemon's PATH (the
  # chirurgeon package bin); build-view cold-starts the org-agent emacs via
  # the absolute $ORG_AGENT_EMACS env (no emacsclient, no daemon). mkAfter
  # appends to the module's own PATH (coreutils/openssh/org-bridge
  # client/voidmaster bin).
  systemd.services.vox-organism.path = lib.mkAfter [
    chirurgeon-pkg
    interrogator-pkg
    remembrancer-pkg
    # Savant/Choirmaster/Factor #+AGENT shells (savant-infer/choirmaster-infer/
    # factor-infer) resolve as bare names on PATH — same gap the
    # interrogator-pkg addition closed. Choirmaster's bins are self-wrapped
    # (runtime deps incl. python/pychromecast/mpc carried via makeWrapper), so
    # choirmaster-pkg is sufficient on PATH. Savant's print-file + Factor's
    # hledger tools are bare + call `lp`/`file`/`hledger`/`git` as bare names,
    # so those runtime deps are added explicitly below.
    savant-pkg
    choirmaster-pkg
    factor-pkg
    # Savant print-file: lp client (cups) + PDF mime validation (poppler-utils
    # for pdftotext/pdfinfo) + file(1) for `file -b --mime-type`. print is
    # non-functional at MVP (no write tool — the Savant can't place a file in
    # the stateDir prison to print), but the deps are forward-wired so a
    # future write-tool round-trip doesn't redeploy for PATH.
    pkgs.cups
    pkgs.poppler-utils
    pkgs.file
    # Factor finance tools: the package wrap deliberately excludes hledger/
    # git/poppler (the module's servicePath carries them — but the daemon
    # path doesn't use the module servicePath). hledger + hledger-utils for
    # hledger-bal/reg/import; git for ledger-commit (local, NO remote/push).
    # poppler-utils deferred (OCR/PDF source not built at MVP).
    pkgs.hledger
    pkgs.hledger-utils
    pkgs.git
  ];
}
