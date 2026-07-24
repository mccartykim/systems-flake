#!/usr/bin/env python3
# =============================================================================
# Hermetic tests for the bridge-scribe forge<->github sync logic.
# =============================================================================
# Exercises sync_repo() against LOCAL bare repos (file:// remotes bypass
# GIT_SSH_COMMAND, so no key/network needed). Verifies the bidirectional
# fast-forward, all-branches, no-prune, no-force contract:
#   - github->forge catch-up (forge starts empty, gets main + other branches)
#   - forge->github propagation (a forge-ahead merge fast-forwards github)
#   - divergence is SAFE (non-ff rejected on both sides, neither repo damaged)
#   - open proposed/ branches on the forge are NOT pruned by github->forge
# Run: python3 hosts/historian/test_bridge_scribe_sync.py
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bridge_scribe_sync import sync_repo  # noqa: E402


def git(args, cwd=None):
    env = dict(os.environ)
    env["GIT_TERMINAL_PROMPT"] = "0"
    r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True,
                       text=True, env=env)
    if r.returncode != 0:
        raise AssertionError("git " + " ".join(args) + " failed: "
                             + (r.stderr or "").strip())
    return r.stdout


def bare(path):
    os.makedirs(path, exist_ok=True)
    git(["init", "--bare", "-b", "main", path])
    return path


def head(bare_repo, ref="main"):
    return git(["--git-dir", bare_repo, "rev-parse", ref]).strip()


def commit(repo, msg, cwd):
    git(["commit", "--allow-empty", "-m", msg], cwd=cwd)
    return git(["rev-parse", "HEAD"], cwd=cwd).strip()


class SyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="synctest-")
        self.cwd = os.getcwd()
        self.github = bare(os.path.join(self.tmp, "github.git"))
        self.forge = bare(os.path.join(self.tmp, "forge.git"))
        self.scratch = os.path.join(self.tmp, "scratch")
        os.makedirs(self.scratch)
        # Seed github with an initial main commit.
        seed = os.path.join(self.tmp, "seed")
        git(["clone", self.github, seed])
        git(["branch", "-M", "main"], cwd=seed)
        self.seed_sha = commit(seed, "init", seed)
        git(["push", "origin", "main"], cwd=seed)
        shutil.rmtree(seed, ignore_errors=True)

    def tearDown(self):
        os.chdir(self.cwd)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _sync(self):
        os.chdir(self.cwd)  # sync_repo chdir's into its own scratch; reset after
        # file:// remotes bypass GIT_SSH_COMMAND; PATH must be present for git.
        git_env = dict(os.environ)
        git_env.pop("GIT_SSH_COMMAND", None)
        sync_repo("test", self.github, self.forge, git_env, self.scratch)
        os.chdir(self.cwd)

    def test_github_to_forge_catchup(self):
        # Forge starts empty; one sync brings forge main up to github.
        self._sync()
        self.assertEqual(head(self.forge), self.seed_sha)
        self.assertEqual(head(self.github), self.seed_sha)

    def test_forge_to_github_propagation(self):
        # A merge that lands on forge (forge ahead) must fast-forward github.
        self._sync()  # forge now has seed
        adv = os.path.join(self.tmp, "adv")
        git(["clone", self.forge, adv])
        merge_sha = commit(adv, "merge-on-forge", adv)
        git(["push", "origin", "main"], cwd=adv)
        shutil.rmtree(adv, ignore_errors=True)
        self._sync()  # forge->github should propagate
        self.assertEqual(head(self.github), merge_sha,
                         "forge merge did not propagate to github")

    def test_other_branches_propagate(self):
        # The user's "other branches as well" requirement: a non-main branch
        # on github mirrors to forge, and vice versa.
        self._sync()
        br = os.path.join(self.tmp, "br")
        git(["clone", self.github, br])
        git(["checkout", "-b", "release"], cwd=br)
        rel_sha = commit(br, "release-cut", br)
        git(["push", "origin", "release"], cwd=br)
        shutil.rmtree(br, ignore_errors=True)
        self._sync()
        self.assertEqual(head(self.forge, "release"), rel_sha,
                         "non-main branch did not mirror github->forge")

    def test_divergence_is_safe(self):
        # Both sides advance the SAME ref with different commits: both pushes
        # are non-fast-forward, both rejected, neither repo is overwritten.
        self._sync()
        # github advance
        g = os.path.join(self.tmp, "g")
        git(["clone", self.github, g])
        g_sha = commit(g, "github-direct", g)
        git(["push", "origin", "main"], cwd=g)
        shutil.rmtree(g, ignore_errors=True)
        # forge advance (different commit, same parent)
        f = os.path.join(self.tmp, "f")
        git(["clone", self.forge, f])
        f_sha = commit(f, "forge-direct", f)
        git(["push", "origin", "main"], cwd=f)
        shutil.rmtree(f, ignore_errors=True)
        self._sync()  # should reject both directions, no damage
        self.assertEqual(head(self.github), g_sha, "github was overwritten on divergence")
        self.assertEqual(head(self.forge), f_sha, "forge was overwritten on divergence")

    def test_forge_proposed_branch_not_pruned(self):
        # An open PR branch on the forge must NOT be deleted by a github->forge
        # push (no --mirror, no --prune). github has no such branch.
        self._sync()
        p = os.path.join(self.tmp, "p")
        git(["clone", self.forge, p])
        git(["checkout", "-b", "proposed/foo"], cwd=p)
        prop_sha = commit(p, "open-pr", p)
        git(["push", "origin", "proposed/foo"], cwd=p)
        shutil.rmtree(p, ignore_errors=True)
        self._sync()  # github->forge runs; must not delete proposed/foo
        self.assertEqual(head(self.forge, "proposed/foo"), prop_sha,
                         "forge proposed/ branch was pruned by sync")


if __name__ == "__main__":
    unittest.main()