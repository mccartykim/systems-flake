#!/usr/bin/env python3
# =============================================================================
# Adversarial trust-boundary tests for the bridge-scribe materialize servitor.
# =============================================================================
# Subprocess-execs the REAL materialize script (single source of truth — the
# same file hosts/historian/bridge-scribe.nix reads into the forced command)
# with crafted author JSON on stdin and asserts the exit code + stderr. Reaches
# every REJECTION path without git/key/network: the script validates the full
# envelope (repo allowlist, branch prefix, shape, per-file path-prisoning)
# BEFORE any clone/key/push, so a bad envelope dies fast at the trust boundary.
# The one ACCEPT-then-fail path (git op, exit 5) needs a real deploy key +
# network and is out of scope here.
#
# Run: python3 hosts/historian/test_bridge_scribe.py
import json
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "bridge_scribe_materialize.py")


def run_scribe(envelope, raw=False):
    """Feed envelope to the materialize script; return (rc, stderr)."""
    stdin = envelope.encode() if raw else json.dumps(envelope).encode()
    # Clean env: no BRIDGE_SCRIBE_DEPLOY_KEY, no GIT_SSH_COMMAND. The script
    # needs none of these to reach any rejection path (it validates first);
    # a fully-valid envelope with no key dies at the key gate (exit 4).
    proc = subprocess.run(
        [sys.executable, SCRIPT],
        input=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env={},
    )
    return proc.returncode, proc.stderr.decode("utf-8", "replace")


def good(**over):
    e = {"repo": "systems-flake", "slug": "fix-foo",
         "branch": "proposed/fix-foo", "commit_msg": "fix foo",
         "files": [{"path": "a.nix", "content": "x"}]}
    e.update(over)
    return e


class RejectMalformedJson(unittest.TestCase):
    def test_not_json(self):
        rc, err = run_scribe("not json at all", raw=True)
        self.assertEqual(rc, 2)
        self.assertIn("malformed JSON", err)

    def test_json_array_not_object(self):
        rc, err = run_scribe([1, 2, 3])
        self.assertEqual(rc, 2)
        self.assertIn("not an object", err)

    def test_json_number_not_object(self):
        rc, _ = run_scribe(42)
        self.assertEqual(rc, 2)


class RejectEnvelopeShape(unittest.TestCase):
    def test_repo_not_in_allowlist(self):
        rc, err = run_scribe(good(repo="organism"))
        self.assertEqual(rc, 3)
        self.assertIn("not in allowlist", err)

    def test_repo_non_string(self):
        rc, _ = run_scribe(good(repo=123))
        self.assertEqual(rc, 3)

    def test_missing_slug(self):
        rc, err = run_scribe(good(slug=""))
        self.assertEqual(rc, 3)
        self.assertIn("slug", err)

    def test_branch_must_start_proposed(self):
        rc, err = run_scribe(good(branch="main"))
        self.assertEqual(rc, 3)
        self.assertIn("proposed/", err)
        self.assertIn("main", err)

    def test_branch_bare_prefix_no_slug(self):
        # "proposed/".startswith("proposed/") is True, so the branch gate is a
        # prefix check, not a slug match — a bare "proposed/" passes it. With a
        # non-empty slug + valid files, validation passes and it dies at the
        # key gate (no key) — exit 4, NOT 3. Documents the prefix semantics.
        rc, _ = run_scribe(good(branch="proposed/"))
        self.assertEqual(rc, 4)

    def test_missing_commit_msg(self):
        rc, err = run_scribe(good(commit_msg=""))
        self.assertEqual(rc, 3)
        self.assertIn("commit_msg", err)

    def test_files_empty_list(self):
        rc, err = run_scribe(good(files=[]))
        self.assertEqual(rc, 3)
        self.assertIn("non-empty", err)

    def test_files_not_a_list(self):
        rc, _ = run_scribe(good(files="not-a-list"))
        self.assertEqual(rc, 3)

    def test_files_missing(self):
        e = good()
        del e["files"]
        rc, _ = run_scribe(e)
        self.assertEqual(rc, 3)


class RejectPathTraversal(unittest.TestCase):
    """Path-prison fires BEFORE clone (fail-fast), so these reach exit 3 with
    no key/git — the trust boundary holds even when no deploy key is staged
    (e.g. a direct forced-command ssh attempt), which is the whole point of
    re-validating on this side of the hop."""

    def test_absolute_path(self):
        rc, err = run_scribe(good(files=[{"path": "/etc/passwd", "content": "x"}]))
        self.assertEqual(rc, 3)
        self.assertIn("escapes repo root", err)

    def test_parent_traversal(self):
        rc, err = run_scribe(good(files=[{"path": "../foo", "content": "x"}]))
        self.assertEqual(rc, 3)
        self.assertIn("escapes repo root", err)

    def test_nested_parent_traversal(self):
        rc, err = run_scribe(good(files=[{"path": "a/../../b", "content": "x"}]))
        self.assertEqual(rc, 3)

    def test_empty_path(self):
        rc, _ = run_scribe(good(files=[{"path": "", "content": "x"}]))
        self.assertEqual(rc, 3)

    def test_file_entry_not_object(self):
        rc, _ = run_scribe(good(files=["not-a-dict"]))
        self.assertEqual(rc, 3)

    def test_non_string_content(self):
        rc, _ = run_scribe(good(files=[{"path": "a.nix", "content": 123}]))
        self.assertEqual(rc, 3)

    def test_path_non_string(self):
        rc, _ = run_scribe(good(files=[{"path": 123, "content": "x"}]))
        self.assertEqual(rc, 3)

    def test_one_bad_path_among_good(self):
        rc, _ = run_scribe(good(files=[
            {"path": "a.nix", "content": "x"},
            {"path": "../evil", "content": "x"},
        ]))
        self.assertEqual(rc, 3)


class ValidEnvelopeNoKey(unittest.TestCase):
    """A fully-valid envelope with no deploy key staged dies at the key gate
    (exit 4) — never reaches git. Proves validation passes and the key is the
    next gate; also that a keyless direct-ssh attempt cannot push."""

    def test_valid_but_no_key(self):
        rc, err = run_scribe(good())
        self.assertEqual(rc, 4)
        self.assertIn("not staged", err)

    def test_valid_multiple_files_no_key(self):
        rc, _ = run_scribe(good(files=[
            {"path": "a.nix", "content": "x"},
            {"path": "b/c.nix", "content": "y"},
        ]))
        self.assertEqual(rc, 4)


class ChirurgeonAllowlist(unittest.TestCase):
    """The Chirurgeon (#62) authors its own chirurgeon_organism repo. A valid
    envelope against it validates + dies at the key gate (exit 4, NOT the
    allowlist reject exit 3) — proving the repo is in REPOS + the shared
    deploy key is the only remaining gate."""

    def test_chirurgeon_repo_in_allowlist(self):
        rc, err = run_scribe(good(repo="chirurgeon_organism"))
        # NOT exit 3 (allowlist reject) — it passed validation + hit the key gate.
        self.assertEqual(rc, 4)
        self.assertNotIn("not in allowlist", err)

    def test_chirurgeon_unrelated_repo_rejected(self):
        # A repo name sharing a prefix must NOT match (exact-allowlist, no
        # substring). "chirurgeon_organism-evil" is rejected at exit 3.
        rc, err = run_scribe(good(repo="chirurgeon_organism-evil"))
        self.assertEqual(rc, 3)
        self.assertIn("not in allowlist", err)


class InterrogatorAllowlist(unittest.TestCase):
    """The Interrogator (#53) authors its own interrogator_organism repo. A
    valid envelope against it validates + dies at the key gate (exit 4, NOT
    the allowlist reject exit 3) — proving the repo is in REPOS + the shared
    deploy key is the only remaining gate. Mirrors the Chirurgeon case."""

    def test_interrogator_repo_in_allowlist(self):
        rc, err = run_scribe(good(repo="interrogator_organism"))
        self.assertEqual(rc, 4)
        self.assertNotIn("not in allowlist", err)

    def test_interrogator_unrelated_repo_rejected(self):
        rc, err = run_scribe(good(repo="interrogator_organism-evil"))
        self.assertEqual(rc, 3)
        self.assertIn("not in allowlist", err)


if __name__ == "__main__":
    unittest.main()