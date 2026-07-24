# =============================================================================
# bridge-scribe dispatch -- the forced-command router.
# =============================================================================
# Single source of truth: hosts/historian/bridge-scribe.nix does
# `pkgs.writeText "bridge-scribe-dispatch.py" (builtins.readFile ./this)` and
# the authorized_keys `command=` execs a shell wrapper that execs THIS.
#
# One fleet key -> one forced command. sshd matches the FIRST authorized_keys
# line for a key, so a key cannot have two different forced commands. To serve
# BOTH the author verb (materialize) AND the read verbs (read/grep) over the
# one key, the forced command is a thin router that picks the verb from
# $SSH_ORIGINAL_COMMAND:
#
#   - empty (the daemon's author hop sends `ssh ... host` with NO command, JSON
#     on stdin) -> `materialize`: exec materialize.py with the JSON on stdin.
#     The author path is UNCHANGED -- it never sets a remote command, so it
#     falls through to materialize by default.
#   - `read` / `grep` (the officer's read tool scripts send `ssh ... host read`
#     / `grep`, with repo/path/pattern as newline-delimited stdin) -> exec
#     read.py with `verb repo path...` as argv (stdin args become argv; argv is
#     list-form, never a shell, so the LLM-supplied repo/path/pattern can never
#     inject).
#
# The dispatcher only routes + allowlists the verb; both children re-validate
# the full envelope on the far side (defense in depth, as materialize already
# did). An unknown verb dies at the boundary with no side effects.
import os
import subprocess
import sys

ALLOWED = ("materialize", "read", "grep")


def die(msg, code=3):
    sys.stderr.write("bridge-scribe dispatch: " + msg + "\n")
    sys.exit(code)


def main():
    raw = (os.environ.get("SSH_ORIGINAL_COMMAND") or "").strip()
    verb = raw.split()[0] if raw else "materialize"
    if verb not in ALLOWED:
        die("unknown verb (allowed: " + ", ".join(ALLOWED) + "): " + repr(verb), 3)

    python = sys.executable
    stdin = sys.stdin.buffer.read()

    if verb == "materialize":
        materialize_py = os.environ.get("BRIDGE_MATERIALIZE_PY")
        if not materialize_py or not os.path.isfile(materialize_py):
            die("materialize module not staged (BRIDGE_MATERIALIZE_PY)", 2)
        # Pass the author JSON straight through; stdout/stderr inherit the ssh
        # session (the PR URL / die message flows back to the daemon).
        proc = subprocess.run([python, materialize_py], input=stdin)
        sys.exit(proc.returncode)

    # read / grep
    read_py = os.environ.get("BRIDGE_READ_PY")
    if not read_py or not os.path.isfile(read_py):
        die("read module not staged (BRIDGE_READ_PY)", 2)
    # stdin args -> argv (newline-delimited repo/path/pattern). list-form argv,
    # no shell. DEVNULL so the child does not re-read the already-consumed stdin.
    lines = stdin.decode("utf-8", "replace").splitlines()
    proc = subprocess.run([python, read_py, verb] + lines, stdin=subprocess.DEVNULL)
    sys.exit(proc.returncode)


if __name__ == "__main__":
    main()