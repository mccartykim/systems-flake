# =============================================================================
# bridge-scribe read — the read-only investigation verb (#127 follow-up).
# =============================================================================
# Single source of truth: hosts/historian/bridge-scribe.nix does
# `pkgs.writeText "bridge-scribe-read.py" (builtins.readFile ./this)` and the
# dispatcher execs it. The adversarial test in test_bridge_scribe_read.py
# subprocess-execs THIS file, so production and test can never drift apart.
#
# The Remembrancer's read tools (read_file / grep) reach this over the SAME
# forced-command ssh hop the author path uses (one fleet key, one scribe). The
# dispatcher passes `verb repo path...` as argv (the verb came from
# $SSH_ORIGINAL_COMMAND; repo/path/pattern came as stdin lines — argv-safe, no
# shell). This script re-validates on the far side of the trust boundary (the
# last gate before a `git clone`), exactly as materialize does.
#
# READ-ONLY by construction: a shallow `git clone --depth 1` into scratch, then
# `cat` (read) or `grep -rn` (grep). It NEVER pushes, commits, writes a file,
# touches the forge, or mutates anything. The clone is thrown away in `finally`.
# The REPOS allowlist is the SAME one materialize owns (imported by path from
# BRIDGE_MATERIALIZE_PY — single source of truth, no drift), so the read verb
# can reach exactly the repos the author verb can, no more.
#
# Die codes mirror materialize: 2 = misuse/bad-args, 3 = validation (repo /
# path / verb), 4 = key not staged, 5 = git/clone op failure.
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

READ_CAP = 32000  # cap one file / one grep dump so it can't dominate the model window


def die(msg, code=1):
    sys.stderr.write("bridge-scribe read: " + msg + "\n")
    sys.exit(code)


def _repos():
    """Load REPOS from the materialize module (single source of truth for the
    allowlist). materialize.py is side-effect-free at import (main() only runs
    under __main__), so importing it is safe."""
    path = os.environ.get("BRIDGE_MATERIALIZE_PY")
    if not path or not os.path.isfile(path):
        die("materialize module not staged (BRIDGE_MATERIALIZE_PY)", 2)
    spec = importlib.util.spec_from_file_location("_scribe_materialize", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, "REPOS", None)


def _bad_path(p):
    """A repo-relative path is bad if absolute, empty, or contains a `..`
    segment. Reached BEFORE the clone (fail-fast), so a traversal attempt dies
    at the trust boundary with no side effects."""
    if not isinstance(p, str) or p == "":
        return True
    if p.startswith("/"):
        return True
    if ".." in p.split("/"):
        return True
    return False


def main():
    args = sys.argv[1:]
    if not args:
        die("no verb", 2)
    verb = args[0]
    if verb not in ("read", "grep"):
        die("unknown verb (read/grep only): " + repr(verb), 3)

    repos = _repos()
    if not isinstance(repos, dict) or not repos:
        die("REPOS allowlist missing", 2)

    if len(args) < 2:
        die("missing repo", 2)
    repo = args[1]
    if not isinstance(repo, str) or repo not in repos:
        die("repo not in allowlist: " + repr(repo), 3)
    github = repos[repo].get("github")
    if not github:
        die("no github remote for " + repr(repo), 3)

    # Validate the FULL request (path-prison + pattern) BEFORE the key check,
    # so a traversal / bad-pattern attempt dies fast at the trust boundary
    # (exit 3) with no side effects -- exactly as materialize validates the full
    # envelope before clone/key. A malformed request must not reach the key
    # gate (exit 4) and look indistinguishable from a valid-but-keyless one.
    if verb == "read":
        if len(args) < 3:
            die("missing path", 2)
        target = args[2]
        if _bad_path(target):
            die("path escapes repo root: " + repr(target), 3)
    else:  # grep
        if len(args) < 3:
            die("missing pattern", 2)
        pattern = args[2]
        if not isinstance(pattern, str) or pattern == "":
            die("empty pattern", 3)
        target = args[3] if len(args) >= 4 else "."
        if _bad_path(target):
            die("path escapes repo root: " + repr(target), 3)

    key_env = repos[repo].get("key_env", "BRIDGE_SCRIBE_DEPLOY_KEY")
    key_path = os.environ.get(key_env)
    if not key_path or not os.path.isfile(key_path):
        die("deploy key not staged", 4)

    git_env = dict(os.environ)
    git_env["GIT_SSH_COMMAND"] = (
        "ssh -i " + key_path +
        " -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" +
        " -o BatchMode=yes"
    )

    scratch = tempfile.mkdtemp(prefix="scribe-read-",
                               dir="/var/lib/bridge-scribe/scratch")
    try:
        # Shallow clone: read-only, no push, so depth 1 is enough + fast.
        subprocess.run(["git", "clone", "--depth", "1", github, scratch],
                       check=True, env=git_env, capture_output=True, text=True)
        full = os.path.join(scratch, target)
        if verb == "read":
            if not os.path.isfile(full):
                sys.stdout.write("(no content found at " + target + ")\n")
                return
            with open(full, "rb") as fh:
                sys.stdout.buffer.write(fh.read(READ_CAP))
            sys.stdout.buffer.flush()
        else:  # grep
            if not os.path.isdir(full):
                sys.stdout.write("(no such directory: " + target + ")\n")
                return
            try:
                # -I: skip binary files; -r: recursive; -n: line numbers; --:
                # end opts so a pattern starting with `-` is a pattern, not a flag.
                proc = subprocess.run(
                    ["grep", "-rIn", "--", pattern, full],
                    capture_output=True, text=True, errors="replace",
                    timeout=60, env=dict(os.environ))
                out = proc.stdout or ""
                sys.stdout.write(out[:READ_CAP])
                if len(out) > READ_CAP:
                    sys.stdout.write("\n(... truncated ...)\n")
                sys.stdout.flush()
            except subprocess.TimeoutExpired:
                sys.stdout.write("(grep timed out)\n")
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        if len(stderr) > 600:
            stderr = stderr[:600]
        die("clone failed (" + str(exc) + "): " + stderr, 5)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    main()