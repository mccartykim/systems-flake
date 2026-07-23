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
  roster = import "${bridgeCrewSrc}/deploy/roster.nix" { inherit lib; };
  # The Chirurgeon's household tools (speak / compel-spirit / ha-get-state /
  # build-view) live in the chirurgeon_organism package bin; medicae-infer
  # dispatches them as bare names on PATH. build-view needs org-agent's
  # emacsclient. Both are mirrored onto the daemon below.
  org-agent-emacs = inputs.org-agent.packages.${pkgs.system}.emacs;
  chirurgeon-pkg = inputs.chirurgeon-organism.packages.${pkgs.system}.default;
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
  # into the daemon's service environment + add the chirurgeon package bin +
  # org-agent-emacs to the daemon's PATH. The daemon's _clean_env_for_organic
  # strips only MATRIX_* (and overrides OFFICER_STATE=VOX_STATE — harmless:
  # medicae-infer reads the officer-specific CHIRURGEON_STATE, not OFFICER_STATE),
  # so HA_TOKEN_FILE / HA_URL / ORG_AGENT_* / TTS_* / CHIRURGEON_STATE pass
  # straight through to the organic child. Inert for the officer-infer
  # officers — they don't read these vars.
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
  users.users.vox-organism.extraGroups = [ "life-coach" ];
  systemd.services.vox-organism.environment = {
    # medicae-infer error-log dir (officer-specific, so the daemon's
    # OFFICER_STATE=VOX_STATE override doesn't collide).
    CHIRURGEON_STATE = "/var/lib/chirurgeon-organism";
    # HA auspex (ha-get-state) + compel-spirit.
    HA_URL = "http://127.0.0.1:8123";
    HA_TOKEN_FILE = config.age.secrets.ha-vox-organism-token.path;
    # Calendar/task view (build-view → org-agent emacs socket).
    ORG_AGENT_SOCKET = "/var/lib/life-coach-agent/emacs/org-agent";
    ORG_AGENT_EMACSCLIENT = "${org-agent-emacs}/bin/emacsclient";
    # speak / lib/tts.py (rung-2 smart-speaker vox).
    TTS_SERVER = "http://total-eclipse.nebula:8091";
    TTS_VOICE = "caine";
    TTS_DEVICE = "Kim's nest hub";
  };
  # medicae-infer dispatches speak/compel-spirit/ha-get-state/build-view/log-
  # observation as bare names → they must be on the daemon's PATH (the
  # chirurgeon package bin); build-view shells out to emacsclient (org-agent-
  # emacs). mkAfter appends to the module's own PATH (coreutils/openssh/
  # org-bridge client/voidmaster bin).
  systemd.services.vox-organism.path = lib.mkAfter [
    chirurgeon-pkg
    org-agent-emacs
  ];
}