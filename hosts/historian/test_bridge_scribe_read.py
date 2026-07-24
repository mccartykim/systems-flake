#!/usr/bin/env python3
# =============================================================================
# Adversarial trust-boundary tests for the bridge-scribe read verb + dispatcher.
# =============================================================================
# Subprocess-execs the REAL read script + the REAL dispatcher (single source of
# truth -- bridge-scribe.nix reads these same files into the forced command) and
# asserts exit code + stderr. Reaches every REJECTION path without git/key/
# network: read.py validates repo allowlist, verb, path-prison, and pattern
# BEFORE any clone/key, so a bad request dies fast at the trust boundary. The
# one ACCEPT-then-fail path (clone, exit 5) needs a real deploy key + network
# and is out of scope here.
#
# Also covers the dispatcher: the author verb (materialize) still routes when
# $SSH_ORIGINAL_COMMAND is empty (the daemon's command-less author hop), read/
# grep route when it is set, and an unknown verb dies at the boundary.
#
# Run: python3 hosts/historian/test_bridge_scribe_read.py
import json
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
READ = os.path.join(HERE, "bridge_scribe_read.py")
DISPATCH = os.path.join(HERE, "bridge_scribe_dispatch.py")
MATERIALIZE = os.path.join(HERE, "bridge_scribe_materialize.py")

# kimb-blog-content + remembrancer_organism are in REPOS (the Remembrancer's
# authorable repos); an unrelated name is not.
ALLOWED_REPO = "kimb-blog-content"
BAD_REPO = "organism"


def run_read(argv):
    """Exec read.py with argv + the materialize-module path it imports REPOS
    from. No deploy key staged -> a fully-valid request dies at the key gate
    (exit 4); validation rejections die at exit 3 first."""
    proc = subprocess.run(
        [sys.executable, READ] + argv,
        input=b"", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env={"BRIDGE_MATERIALIZE_PY": MATERIALIZE},
    )
    return proc.returncode, proc.stderr.decode("utf-8", "replace")


def run_dispatch(ssh_original_command, stdin):
    """Exec dispatch.py with a crafted $SSH_ORIGINAL_COMMAND + stdin."""
    env = {
        "BRIDGE_MATERIALIZE_PY": MATERIALIZE,
        "BRIDGE_READ_PY": READ,
    }
    if ssh_original_command is not None:
        env["SSH_ORIGINAL_COMMAND"] = ssh_original_command
    proc = subprocess.run(
        [sys.executable, DISPATCH],
        input=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
    )
    return proc.returncode, proc.stderr.decode("utf-8", "replace")


class ReadRejectMisuse(unittest.TestCase):
    def test_no_args(self):
        rc, _ = run_read([])
        self.assertEqual(rc, 2)

    def test_missing_repo(self):
        rc, _ = run_read(["read"])
        self.assertEqual(rc, 2)

    def test_read_missing_path(self):
        rc, _ = run_read(["read", ALLOWED_REPO])
        self.assertEqual(rc, 2)

    def test_grep_missing_pattern(self):
        rc, _ = run_read(["grep", ALLOWED_REPO])
        self.assertEqual(rc, 2)


class ReadRejectVerb(unittest.TestCase):
    def test_unknown_verb(self):
        rc, err = run_read(["bogus", ALLOWED_REPO, "README.md"])
        self.assertEqual(rc, 3)
        self.assertIn("read/grep only", err)

    def test_materialize_verb_not_allowed_here(self):
        # materialize is a separate path; read.py only knows read/grep.
        rc, _ = run_read(["materialize", ALLOWED_REPO, "README.md"])
        self.assertEqual(rc, 3)


class ReadRejectRepo(unittest.TestCase):
    def test_repo_not_in_allowlist(self):
        rc, err = run_read(["read", BAD_REPO, "README.md"])
        self.assertEqual(rc, 3)
        self.assertIn("not in allowlist", err)

    def test_repo_non_string_passes_type_but_missing(self):
        # A repo name sharing a prefix must NOT match (exact allowlist).
        rc, err = run_read(["read", ALLOWED_REPO + "-evil", "README.md"])
        self.assertEqual(rc, 3)
        self.assertIn("not in allowlist", err)


class ReadRejectPath(unittest.TestCase):
    """Path-prison fires BEFORE clone (fail-fast), so these reach exit 3 with no
    key/git -- the trust boundary holds even when no deploy key is staged."""

    def test_absolute_path(self):
        rc, err = run_read(["read", ALLOWED_REPO, "/etc/passwd"])
        self.assertEqual(rc, 3)
        self.assertIn("escapes repo root", err)

    def test_parent_traversal(self):
        rc, err = run_read(["read", ALLOWED_REPO, "../etc/passwd"])
        self.assertEqual(rc, 3)
        self.assertIn("escapes repo root", err)

    def test_nested_parent_traversal(self):
        rc, _ = run_read(["read", ALLOWED_REPO, "a/../../b"])
        self.assertEqual(rc, 3)

    def test_empty_path(self):
        rc, _ = run_read(["read", ALLOWED_REPO, ""])
        self.assertEqual(rc, 3)

    def test_grep_path_traversal(self):
        rc, err = run_read(["grep", ALLOWED_REPO, "draft: true", "../x"])
        self.assertEqual(rc, 3)
        self.assertIn("escapes repo root", err)

    def test_grep_absolute_path(self):
        rc, _ = run_read(["grep", ALLOWED_REPO, "draft: true", "/etc"])
        self.assertEqual(rc, 3)


class ReadRejectPattern(unittest.TestCase):
    def test_grep_empty_pattern(self):
        rc, err = run_read(["grep", ALLOWED_REPO, ""])
        self.assertEqual(rc, 3)
        self.assertIn("empty pattern", err)


class ReadValidNoKey(unittest.TestCase):
    """A fully-valid read/grep request with no deploy key dies at the key gate
    (exit 4) -- never reaches git. Proves validation passes first + that a
    keyless direct-ssh attempt cannot read (the clone is gated on the key)."""

    def test_read_valid_but_no_key(self):
        rc, err = run_read(["read", ALLOWED_REPO, "README.md"])
        self.assertEqual(rc, 4)
        self.assertIn("not staged", err)

    def test_grep_valid_but_no_key(self):
        rc, err = run_read(["grep", ALLOWED_REPO, "draft: true"])
        self.assertEqual(rc, 4)
        self.assertNotIn("not in allowlist", err)

    def test_grep_valid_with_path_no_key(self):
        rc, _ = run_read(["grep", ALLOWED_REPO, "draft: true", "content/blog"])
        self.assertEqual(rc, 4)


class DispatchMaterializeUnchanged(unittest.TestCase):
    """The author path sends `ssh ... host` with NO command + JSON on stdin.
    $SSH_ORIGINAL_COMMAND is unset -> the dispatcher defaults to materialize +
    passes the JSON through. A valid author envelope dies at materialize's key
    gate (exit 4) -- proving the author verb routes unchanged through dispatch."""

    def _author(self, **over):
        e = {"repo": "systems-flake", "slug": "fix-foo",
             "branch": "proposed/fix-foo", "commit_msg": "fix foo",
             "files": [{"path": "a.nix", "content": "x"}]}
        e.update(over)
        return e

    def test_no_command_routes_to_materialize(self):
        rc, err = run_dispatch(None, json.dumps(self._author()).encode())
        self.assertEqual(rc, 4)  # materialize key gate
        self.assertNotIn("unknown verb", err)

    def test_empty_command_routes_to_materialize(self):
        rc, _ = run_dispatch("   ", json.dumps(self._author()).encode())
        self.assertEqual(rc, 4)


class DispatchReadRoute(unittest.TestCase):
    """read/grep arrive as `ssh ... host read` / `grep` with repo/path/pattern
    as stdin lines. The dispatcher parses the verb from $SSH_ORIGINAL_COMMAND
    + the args from stdin, then execs read.py with them as argv."""

    def test_read_routes_through_dispatch(self):
        rc, err = run_dispatch("read",
                                (ALLOWED_REPO + "\nREADME.md\n").encode())
        self.assertEqual(rc, 4)  # read key gate
        self.assertNotIn("unknown verb", err)

    def test_grep_routes_through_dispatch(self):
        rc, _ = run_dispatch("grep",
                             (ALLOWED_REPO + "\ndraft: true\n").encode())
        self.assertEqual(rc, 4)

    def test_read_rejects_bad_repo_through_dispatch(self):
        rc, err = run_dispatch("read", (BAD_REPO + "\nREADME.md\n").encode())
        self.assertEqual(rc, 3)
        self.assertIn("not in allowlist", err)

    def test_read_rejects_path_traversal_through_dispatch(self):
        rc, err = run_dispatch("read", (ALLOWED_REPO + "\n../etc\n").encode())
        self.assertEqual(rc, 3)
        self.assertIn("escapes repo root", err)


class DispatchRejectUnknownVerb(unittest.TestCase):
    def test_unknown_verb_rejected(self):
        rc, err = run_dispatch("rm -rf /", b"")
        self.assertEqual(rc, 3)
        self.assertIn("unknown verb", err)

    def test_evil_verb_rejected(self):
        rc, _ = run_dispatch("shellout", b"")
        self.assertEqual(rc, 3)


if __name__ == "__main__":
    unittest.main()