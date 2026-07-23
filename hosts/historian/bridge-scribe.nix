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
# this materialize script, no pty, no forwarding. The fleet key authenticates
# as the bridge-scribe user and can do NOTHING else.
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

  # The forced command the fleet key runs. Sets PATH (git/ssh/python/coreutils)
  # + exports the shared deploy-key agenix path as env the python reads, then
  # execs the python. stdin (the author JSON) flows straight through.
  materialize = pkgs.writeShellScript "bridge-scribe-materialize" ''
    set -eu
    export PATH=${lib.makeBinPath [pkgs.git pkgs.openssh pkgs.python3 pkgs.coreutils]}
    export BRIDGE_SCRIBE_DEPLOY_KEY="${config.age.secrets.deploy-key-bridge-scribe.path}"
    exec ${pkgs.python3}/bin/python3 ${materializePy}
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
        ''command="${materialize}",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding ${fleetKey}''
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

    assertions = [
      {
        assertion = config.services.openssh.enable;
        message = "services.bridge-scribe is enabled but services.openssh is not — the fleet key reaches the forced command over ssh. Enable services.openssh on this host.";
      }
    ];
  };
}