# =============================================================================
# bridge-scribe sync — keeps the forge + github mirrored (all branches).
# =============================================================================
# Run by the bridge-sync systemd timer on historian (every 10 min). The forge
# (#125) is the PR review surface; github stays the nix-fetch canonical. This
# bridges the two so a merged forge PR propagates to github AND a direct github
# push (the Lord-Captain at their workstation) mirrors back to the forge —
# bidirectionally, all heads, the user's "other branches as well" requirement.
#
# Per repo: clone github (full), add the forge remote, fetch forge, then push
# heads github->forge (fast-forward only) THEN forge->github (fast-forward
# only). Order matters: the ahead side fast-forwards the behind side; if both
# diverged with different commits (a true conflict — a forge merge AND a direct
# github push to the same ref), the non-fast-forward push is REJECTED and that
# ref is logged + skipped, no damage. No --force, no --mirror, no --prune: open
# `proposed/` PR branches on the forge are never deleted, and github branches
# absent from the forge are never deleted either.
#
# ONE deploy key (BRIDGE_SCRIBE_DEPLOY_KEY) authenticates to both remotes —
# the mccartykim account key on github + the same key registered on the forge
# kimb user. No new secret, no private key stored in forge state (the scribe
# holds the only copy, in /run/agenix).
import os
import shutil
import subprocess
import sys
import tempfile

# Mirrors bridge_scribe_materialize.py's REPOS (kept in sync by hand; the two
# scripts live in the same dir + are reviewed together).
REPOS = {
    "systems-flake": {
        "github": "git@github.com:mccartykim/systems-flake.git",
        # forge SSH user is `forgejo` (NixOS RUN_USER), not `git` — see
        # bridge_scribe_materialize.py for the rationale.
        "forge": "ssh://forgejo@10.100.0.10:2222/kimb/systems-flake.git",
    },
    "chirurgeon_organism": {
        "github": "git@github.com:mccartykim/chirurgeon_organism.git",
        "forge": "ssh://forgejo@10.100.0.10:2222/kimb/chirurgeon_organism.git",
    },
    "interrogator_organism": {
        "github": "git@github.com:mccartykim/interrogator_organism.git",
        "forge": "ssh://forgejo@10.100.0.10:2222/kimb/interrogator_organism.git",
    },
    # The Remembrancer's prose + seed repos — mirror the SAME THREE entries
    # here as in bridge_scribe_materialize.py (kept in sync by hand; no
    # codegen links them). Forgetting a sync entry means a merged forge PR for
    # a prose repo won't propagate back to github. The shared
    # BRIDGE_SCRIBE_DEPLOY_KEY auths to all three (mccartykim account key).
    "remembrancer_organism": {
        "github": "git@github.com:mccartykim/remembrancer_organism.git",
        "forge": "ssh://forgejo@10.100.0.10:2222/kimb/remembrancer_organism.git",
    },
    "kimb-blog-content": {
        "github": "git@github.com:mccartykim/kimb-blog-content.git",
        "forge": "ssh://forgejo@10.100.0.10:2222/kimb/kimb-blog-content.git",
    },
    "mist-blog": {
        "github": "git@github.com:mccartykim/mist-blog.git",
        "forge": "ssh://forgejo@10.100.0.10:2222/kimb/mist-blog.git",
    },
}


def log(msg):
    sys.stderr.write("bridge-sync: " + msg + "\n")
    sys.stderr.flush()


def run_soft(args, env=None):
    return subprocess.run(args, env=env, capture_output=True, text=True)


def sync_repo(repo, github, forge, git_env, scratch_root):
    # Two --mirror clones (bare; all source heads land as refs/heads/*, so a
    # `refs/heads/*:refs/heads/*` push carries EVERY branch, not just the
    # default — the user's "other branches as well" requirement. A mirror
    # clone has no working tree, so we drive it with --git-dir, no chdir.)
    # github -> forge first (catch forge up), then forge -> github
    # (propagate merges). Both fast-forward only: a non-ff (forge ahead, or a
    # true divergence) is rejected for that ref + logged; no --force, no
    # --prune, so open proposed/ branches + github-only branches are untouched.
    gdir = tempfile.mkdtemp(prefix="sync-g-" + repo + "-", dir=scratch_root)
    fdir = tempfile.mkdtemp(prefix="sync-f-" + repo + "-", dir=scratch_root)
    try:
        rg = run_soft(["git", "clone", "--mirror", github, gdir], env=git_env)
        if rg.returncode != 0:
            log(repo + ": clone --mirror github failed: "
                + (rg.stderr or "").strip()[:300])
            return
        r1 = run_soft(["git", "--git-dir", gdir, "push", forge,
                       "refs/heads/*:refs/heads/*"], env=git_env)
        if r1.returncode != 0:
            log(repo + ": github->forge non-ff (forge ahead?) "
                + (r1.stderr or "").strip()[:200])
        rf = run_soft(["git", "clone", "--mirror", forge, fdir], env=git_env)
        if rf.returncode != 0:
            log(repo + ": clone --mirror forge failed: "
                + (rf.stderr or "").strip()[:300])
            return
        r2 = run_soft(["git", "--git-dir", fdir, "push", github,
                       "refs/heads/*:refs/heads/*"], env=git_env)
        if r2.returncode != 0:
            log(repo + ": forge->github non-ff (diverged?) "
                + (r2.stderr or "").strip()[:200])
        log(repo + ": synced (g->f=" + str(r1.returncode)
            + " f->g=" + str(r2.returncode) + ")")
    finally:
        shutil.rmtree(gdir, ignore_errors=True)
        shutil.rmtree(fdir, ignore_errors=True)


def main():
    key_path = os.environ.get("BRIDGE_SCRIBE_DEPLOY_KEY")
    if not key_path or not os.path.isfile(key_path):
        log("deploy key not staged (BRIDGE_SCRIBE_DEPLOY_KEY) — aborting")
        sys.exit(1)
    scratch_root = "/var/lib/bridge-scribe/scratch"
    if not os.path.isdir(scratch_root):
        log("scratch root missing: " + scratch_root)
        sys.exit(1)
    git_env = dict(os.environ)
    git_env["GIT_SSH_COMMAND"] = (
        "ssh -i " + key_path +
        " -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" +
        " -o BatchMode=yes"
    )
    for repo, remotes in REPOS.items():
        try:
            sync_repo(repo, remotes["github"], remotes["forge"],
                      git_env, scratch_root)
        except Exception as e:  # noqa: BLE001 — never let one repo kill the run
            log(repo + ": exception: " + str(e)[:300])


if __name__ == "__main__":
    main()