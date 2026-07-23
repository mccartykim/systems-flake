# =============================================================================
# bridge-scribe materialize — the forced-command authoring servitor (#60).
# =============================================================================
# Single source of truth: hosts/historian/bridge-scribe.nix does
# `pkgs.writeText "bridge-scribe-materialize.py" (builtins.readFile ./this)`
# and the forced command execs it. The adversarial exit-code test in
# test_bridge_scribe.py subprocess-execs THIS file, so production and the test
# can never drift apart.
#
# Re-validates the officer's `author` envelope on the far side of the trust
# boundary (the daemon on rich-evans already validated, but this is the last
# gate before `git push` to a shared repo, so it never trusts upstream). The
# FULL envelope — repo allowlist, branch prefix, shape, and per-file path
# prisoning — is validated BEFORE the key check and any clone, so a malformed
# envelope dies fast at the boundary with zero side effects (and the path-prison
# check is reachable without a staged deploy key, e.g. a direct forced-command
# ssh attempt). Branch MUST start with `proposed/`; file paths MUST be relative
# and prisoned under the scratch root (no leading `/`, no `..` segment).
import json
import os
import shutil
import subprocess
import sys
import tempfile

# repo -> {remote, key_env}. One SHARED deploy key (BRIDGE_SCRIBE_DEPLOY_KEY)
# serves every repo — the per-repo scope is this allowlist, not the key. The
# key PATH comes from env (set by the shell wrapper, which bakes the agenix
# /run/agenix path). Pilot only; add repos here as officers gain scope (#64).
REPOS = {
    "systems-flake": {
        "remote": "git@github.com:mccartykim/systems-flake.git",
        "key_env": "BRIDGE_SCRIBE_DEPLOY_KEY",
    },
}


def die(msg, code=1):
    sys.stderr.write("bridge-scribe: " + msg + "\n")
    sys.exit(code)


def run(args, env=None):
    return subprocess.run(args, check=True, env=env,
                           capture_output=True, text=True)


def validate_files(files):
    # Prison every file path under the repo root. Called BEFORE clone/key/push
    # so a traversal attempt fails fast at the trust boundary with no side
    # effects. Returns None on ok, or an error message on the first violation.
    if not isinstance(files, list) or not files:
        return "files must be a non-empty list"
    for f in files:
        if not isinstance(f, dict):
            return "file entry is not an object"
        path = f.get("path")
        content = f.get("content")
        if not isinstance(path, str) or not path:
            return "bad file path: " + repr(path)
        if path.startswith("/") or ".." in path.split("/"):
            return "file path escapes repo root: " + repr(path)
        if not isinstance(content, str):
            return "bad content for " + repr(path)
    return None


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
    err = validate_files(files)
    if err:
        die(err, 3)

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
            # Paths + contents already validated by validate_files above.
            dest = os.path.join(scratch, f["path"])
            parent = os.path.dirname(dest)
            if parent:
                os.makedirs(parent, exist_ok=True)
            with open(dest, "w") as fh:
                fh.write(f["content"])
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