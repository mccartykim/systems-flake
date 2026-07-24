# =============================================================================
# bridge-scribe — the authoring servitor on historian.
# =============================================================================
# The #60 PR-authoring loop's "lobotomized cipher-hand" (BRIDGE_CREW §three-tier
# model: officer=persona on rich-evans, servitor=sandboxed coding executor here
# on historian, servoskull=hardware retinue). The vox-organism daemon on
# rich-evans carries an officer's `author` envelope here over a forced-command
# ssh hop (the fleet-internal key, agenix on rich-evans); this servitor clones
# a fresh PLAIN-GIT scratch copy of the target repo (NO jj — the officer never
# touches jj, the user fetches+jj-merges on their own workstation), writes the
# emitted files verbatim, commits on `proposed/<slug>`, and pushes the named
# branch with the shared GitHub deploy key. The branch name comes
# back over ssh stdout to the daemon, which posts it to the room.
#
# Why historian (not rich-evans): rich-evans is an antique mini PC that must
# not run builds or grow clones; historian is the 24-core build machine with
# 30G tmpfs for scratch. Fleet-internal over Nebula.
#
# Pilot tier (locked by the Lord-Captain 2026-07-22): a confined service user +
# scratch + one deploy key, NO VM, one-pass patch the Lord-Captain reviews on
# the branch.
#
# ONE shared key, NOT one per repo. The key is registered as a mccartykim
# ACCOUNT SSH key (titled "bridge-scribe service"), NOT a per-repo deploy
# key — so it has write access to every mccartykim/* repo and needs NO
# per-repo registration (GitHub's one-key-one-repo rule makes a shared
# deploy key unworkable; the account key sidesteps it). Justification for
# one key over per-repo: every authorable repo's key would live in the same
# /run/agenix on this one host, owned by this one user, used by this one
# forced-command process — so per-repo keys buy no real blast-radius
# isolation (anyone who can read one can read them all). The per-repo SCOPE
# is enforced in CODE, not by key scoping: the REPOS allowlist below (+ the
# daemon's OFFICER_REPOS) decides which repo a request may touch, and the
# key only ever reaches github through this forced command. So one key is
# the proxy's single credential — like a reverse proxy holding one backend
# credential and routing by the request. Rotate once; extend the REPOS map
# as officers gain scope (#64).
#
# The forced command mirrors modules/distributed-builds.nix:78 (the
# nix-daemon --stdio builder-only key): a pubkey entry restricted to exactly
# this dispatch router, no pty, no forwarding. The fleet key authenticates as
# the bridge-scribe user and can reach only `materialize` (author) + `read` /
# `grep` (read-only investigation) — verbs the dispatcher allowlists; anything
# else dies at the boundary. The author verb is unchanged; the read verbs
# (#127 follow-up) let the Remembrancer see its authorable repos.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.bridge-scribe;

  # The materialize logic, in python (json parse + git). Single source of
  # truth: the committed ./bridge_scribe_materialize.py, read verbatim into the
  # store here (no '' string, so no Nix-vs-python drift) and exec'd by the
  # forced command below. The adversarial exit-code test in
  # ./test_bridge_scribe.py subprocess-execs that same file. Re-validates the
  # envelope on this side of the trust boundary: the daemon already validated,
  # but this is the last gate before `git push` to a shared repo, so it never
  # trusts upstream. Branch MUST start with `proposed/`, repo MUST be in the
  # allowlist map, file paths MUST be relative and prisoned under the scratch
  # root — and the FULL envelope (incl. path-prisoning) is validated BEFORE the
  # key check + clone, so a malformed envelope dies fast with no side effects.
  materializePy = pkgs.writeText "bridge-scribe-materialize.py"
    (builtins.readFile ./bridge_scribe_materialize.py);

  # The read-only investigation verb (#127 follow-up): the Remembrancer's
  # read_file / grep tools reach repo content over the SAME forced-command hop
  # as the author path. Read-only by construction (shallow clone + cat/grep, no
  # push/commit/forge). REPOS is imported from materializePy below so the
  # allowlist stays a single source of truth (no drift between verbs).
  readPy = pkgs.writeText "bridge-scribe-read.py"
    (builtins.readFile ./bridge_scribe_read.py);

  # The router that the fleet key's forced command runs. One key -> one forced
  # command (sshd matches the first authorized_keys line for a key), so serving
  # BOTH the author verb (materialize) AND the read verbs (read/grep) needs a
  # dispatcher: verb from $SSH_ORIGINAL_COMMAND (empty -> materialize, so the
  # daemon's command-less author hop is unchanged), args via stdin. See
  # bridge_scribe_dispatch.py.
  dispatchPy = pkgs.writeText "bridge-scribe-dispatch.py"
    (builtins.readFile ./bridge_scribe_dispatch.py);

  # The forced command the fleet key runs. Sets PATH (git/ssh/python/coreutils/
  # gnugrep -- grep for the read verb) + exports the shared deploy-key agenix
  # path + the forge URL + the forge API token file + the child-script store
  # paths, then execs the dispatcher. stdin flows straight through to the
  # chosen child. The forge token is the scribe's REST API credential for
  # opening PRs (write:repository+write:issue only); push to the forge uses the
  # SAME deploy key over :2222 (registered on the forge kimb user), not the
  # token. read.py needs no forge token, but it shares this env harmlessly.
  dispatch = pkgs.writeShellScript "bridge-scribe-dispatch" ''
    set -eu
    export PATH=${lib.makeBinPath [pkgs.git pkgs.openssh pkgs.python3 pkgs.coreutils pkgs.gnugrep]}
    export BRIDGE_SCRIBE_DEPLOY_KEY="${config.age.secrets.deploy-key-bridge-scribe.path}"
    export FORGE_URL="http://10.100.0.10:3000"
    export FORGE_TOKEN_FILE="${config.age.secrets.forge-bot-token.path}"
    export BRIDGE_MATERIALIZE_PY="${materializePy}"
    export BRIDGE_READ_PY="${readPy}"
    exec ${pkgs.python3}/bin/python3 ${dispatchPy}
  '';

  # The bidirectional forge<->github heads sync (#125 Phase D). Single source of
  # truth: the committed ./bridge_scribe_sync.py, read verbatim into the store
  # here. Run by the bridge-sync systemd timer below every 10 min; reuses the
  # same deploy key (authenticates to both remotes). No new secret.
  syncPy = pkgs.writeText "bridge-scribe-sync.py"
    (builtins.readFile ./bridge_scribe_sync.py);

  syncRun = pkgs.writeShellScript "bridge-scribe-sync" ''
    set -eu
    export PATH=${lib.makeBinPath [pkgs.git pkgs.openssh pkgs.python3 pkgs.coreutils]}
    export BRIDGE_SCRIBE_DEPLOY_KEY="${config.age.secrets.deploy-key-bridge-scribe.path}"
    exec ${pkgs.python3}/bin/python3 ${syncPy}
  '';

  # The fleet-internal pubkey (rich-evans -> historian). Generated in the same
  # 40k_bridge session that wired the daemon side; private half is agenix on
  # rich-evans (bridge-fleet-ssh-key.age). Forced to ONLY this materialize script.
  fleetKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJkCorkwI7RWuRNFg241GpMSj2ZE2rxgF+IPoPF7E8wN bridge-fleet (rich-evans->historian forced-command)";
in {
  options.services.bridge-scribe = {
    enable = lib.mkEnableOption "bridge-scribe authoring servitor (forced-command ssh target for officer author requests)";
  };

  config = lib.mkIf cfg.enable {
    users.users.bridge-scribe = {
      isSystemUser = true;
      group = "bridge-scribe";
      home = "/var/lib/bridge-scribe";
      homeMode = "0750";
      createHome = true;
      # sshd runs the forced command via the login shell, so this needs a real
      # shell (not nologin) — the command is prisoned by authorized_keys, not
      # by the shell.
      shell = pkgs.bash;
      openssh.authorizedKeys.keys = [
        ''command="${dispatch}",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding ${fleetKey}''
      ];
    };
    users.groups.bridge-scribe = {};

    systemd.tmpfiles.rules = [
      "d /var/lib/bridge-scribe             0750 bridge-scribe bridge-scribe -"
      "d /var/lib/bridge-scribe/scratch      0750 bridge-scribe bridge-scribe -"
    ];

    # The shared GitHub key (an mccartykim account SSH key titled
    # "bridge-scribe service", NOT a per-repo deploy key — write access to
    # every mccartykim/* repo, no per-repo registration). Lives ONLY on
    # historian; the daemon on rich-evans never sees it. The fleet key
    # authenticates as bridge-scribe and the forced command reads this path
    # via the BRIDGE_SCRIBE_DEPLOY_KEY env the wrapper bakes in.
    age.secrets.deploy-key-bridge-scribe = {
      file = ../../secrets/deploy-key-bridge-scribe.age;
      owner = "bridge-scribe";
      mode = "0400";
    };

    # Forgejo application token for opening PRs on the Nebula-only forge (REST
    # API only; push uses the shared deploy key over :2222). write:repository +
    # write:issue, no write:user — decrypted on historian only (owner
    # bridge-scribe, 0400). See secrets/forge-bot-token.age + the comment there.
    age.secrets.forge-bot-token = {
      file = ../../secrets/forge-bot-token.age;
      owner = "bridge-scribe";
      mode = "0400";
    };

    # Bidirectional forge<->github heads sync (#125 Phase D). Runs as the
    # bridge-scribe service user so it can read the deploy key + forge token in
    # /run/agenix. No state of its own; the scratch dir is shared with
    # materialize. 10-min cadence bounds forge/github drift; a oneshot can't
    # overlap itself (systemd won't start a second instance while one runs).
    systemd.services.bridge-sync = {
      description = "bridge-scribe forge<->github mirror sync";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        User = "bridge-scribe";
        Group = "bridge-scribe";
        ExecStart = "${syncRun}";
        PrivateTmp = true;
      };
    };
    systemd.timers.bridge-sync = {
      description = "bridge-scribe forge<->github mirror sync (10 min)";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "10min";
        Persistent = true;
      };
    };

    assertions = [
      {
        assertion = config.services.openssh.enable;
        message = "services.bridge-scribe is enabled but services.openssh is not — the fleet key reaches the forced command over ssh. Enable services.openssh on this host.";
      }
    ];
  };
}