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
# branch with the repo's per-repo GitHub deploy key. The branch name comes
# back over ssh stdout to the daemon, which posts it to the room.
#
# Why historian (not rich-evans): rich-evans is an antique mini PC that must
# not run builds or grow clones; historian is the 24-core build machine with
# 30G tmpfs for scratch. Fleet-internal over Nebula.
#
# Pilot tier (locked by the Lord-Captain 2026-07-22): a confined service user +
# scratch + one deploy key, NO VM, one-pass patch the Lord-Captain reviews on
# the branch. The repo→deploy-key map below starts with the single pilot repo
# (systems-flake / Void-Master); extend the map + add deploy-key age.secrets as
# more officers gain authoring scope (#64 capability matrix).
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

  # The materialize logic, in python (json parse + git). Kept in a '' string so
  # backslash escapes (\n in f-strings) survive verbatim — Nix "" strings would
  # eat them. Re-validates the envelope on this side of the trust boundary: the
  # daemon already validated, but this is the last gate before `git push` to a
  # shared repo, so it never trusts upstream. Branch MUST start with
  # `proposed/`, repo MUST be in the allowlist map, file paths MUST be relative
  # and prisoned under the scratch root.
  materializePy = pkgs.writeText "bridge-scribe-materialize.py" ''
    import json, os, subprocess, sys, tempfile, shutil

    # repo -> {remote, key_env}. The deploy-key PATHS come from env (set by the
    # shell wrapper, which bakes the agenix /run/agenix paths). Pilot only.
    REPOS = {
        "systems-flake": {
            "remote": "git@github.com:mccartykim/systems-flake.git",
            "key_env": "SYSTEMS_FLAKE_DEPLOY_KEY",
        },
    }

    def die(msg, code=1):
        sys.stderr.write("bridge-scribe: " + msg + "\n")
        sys.exit(code)

    def run(args, env=None):
        return subprocess.run(args, check=True, env=env,
                               capture_output=True, text=True)

    def main():
        try:
            req = json.load(sys.stdin)
        except Exception as e:
            die("malformed JSON on stdin: " + str(e), 2)
        if not isinstance(req, dict):
            die("envelope is not an object", 2)

        repo = req.get("repo")
        slug = req.get("slug")
        branch = req.get("branch")
        commit_msg = req.get("commit_msg")
        files = req.get("files")

        if not isinstance(repo, str) or repo not in REPOS:
            die("repo not in allowlist: " + repr(repo), 3)
        if not isinstance(slug, str) or not slug:
            die("missing slug", 3)
        if not isinstance(branch, str) or not branch.startswith("proposed/"):
            die("branch must start with proposed/: " + repr(branch), 3)
        if not isinstance(commit_msg, str) or not commit_msg:
            die("missing commit_msg", 3)
        if not isinstance(files, list) or not files:
            die("files must be a non-empty list", 3)

        key_path = os.environ.get(REPOS[repo]["key_env"])
        if not key_path or not os.path.isfile(key_path):
            die("deploy key for " + repo + " not staged", 4)

        remote = REPOS[repo]["remote"]
        git_env = dict(os.environ)
        git_env["GIT_SSH_COMMAND"] = (
            "ssh -i " + key_path +
            " -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" +
            " -o BatchMode=yes"
        )

        scratch = tempfile.mkdtemp(prefix="scribe-",
                                   dir="/var/lib/bridge-scribe/scratch")
        try:
            # Full clone (not --depth 1): a shallow clone can reject the push of
            # a new branch on some servers. systems-flake is small; tmpfs is 30G.
            run(["git", "clone", remote, scratch], env=git_env)
            os.chdir(scratch)
            for f in files:
                if not isinstance(f, dict):
                    die("file entry is not an object", 3)
                path = f.get("path")
                content = f.get("content")
                if not isinstance(path, str) or not path:
                    die("bad file path: " + repr(path), 3)
                if path.startswith("/") or ".." in path.split("/"):
                    die("file path escapes repo root: " + repr(path), 3)
                if not isinstance(content, str):
                    die("bad content for " + repr(path), 3)
                dest = os.path.join(scratch, path)
                parent = os.path.dirname(dest)
                if parent:
                    os.makedirs(parent, exist_ok=True)
                with open(dest, "w") as fh:
                    fh.write(content)
            run(["git", "add", "-A"])
            ident_env = dict(os.environ,
                             GIT_AUTHOR_NAME="bridge-scribe",
                             GIT_AUTHOR_EMAIL="bridge-scribe@fleet",
                             GIT_COMMITTER_NAME="bridge-scribe",
                             GIT_COMMITTER_EMAIL="bridge-scribe@fleet")
            run(["git", "commit", "-m", commit_msg], env=ident_env)
            # No --force: a re-push of an existing proposed/<slug> is rejected
            # (non-fast-forward from a fresh clone). The officer re-slugs. This
            # honors the standing "no --force on any VCS op" rule.
            run(["git", "push", "origin", "HEAD:refs/heads/" + branch],
                env=git_env)
            sys.stdout.write(branch + "\n")
        except subprocess.CalledProcessError as e:
            stderr = (e.stderr or "").strip()
            if len(stderr) > 600:
                stderr = stderr[:600]
            die("git op failed (" + str(e) + "): " + stderr, 5)
        finally:
            shutil.rmtree(scratch, ignore_errors=True)

    if __name__ == "__main__":
        main()
  '';

  # The forced command the fleet key runs. Sets PATH (git/ssh/python/coreutils)
  # + exports the deploy-key agenix paths as env the python reads per-repo, then
  # execs the python. stdin (the author JSON) flows straight through.
  materialize = pkgs.writeShellScript "bridge-scribe-materialize" ''
    set -eu
    export PATH=${lib.makeBinPath [pkgs.git pkgs.openssh pkgs.python3 pkgs.coreutils]}
    export SYSTEMS_FLAKE_DEPLOY_KEY="${config.age.secrets.deploy-key-systems-flake.path}"
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

    # The systems-flake GitHub deploy key (write, scoped to the one repo). Lives
    # ONLY on historian; the daemon on rich-evans never sees it. The fleet key
    # authenticates as bridge-scribe and the forced command reads this path via
    # the SYSTEMS_FLAKE_DEPLOY_KEY env the wrapper bakes in.
    age.secrets.deploy-key-systems-flake = {
      file = ../../secrets/deploy-key-systems-flake.age;
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