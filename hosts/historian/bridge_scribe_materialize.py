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
#
# Forge flow (#125): the PR review surface is the Nebula-only Forgejo on
# historian (10.100.0.10:3000 / :2222), NOT github. This script clones github
# (current main — github stays the nix-fetch remote; the bootstrap-cycle
# invariant forbids repointing systems-flake's own inputs at the forge),
# catches the forge up (pushes github heads -> forge, fast-forward only), then
# branches `proposed/<slug>` off forge/main, pushes the branch to the FORGE,
# and opens a forge pull request via the REST API (the forge-bot-token). The
# forge PR URL comes back on stdout for the daemon to post. Merges propagate
# back to github via the separate bridge-sync timer (bidirectional heads sync,
# same deploy key) — see bridge_scribe_sync.py. One deploy key authenticates to
# BOTH github (mccartykim account key) and the forge (registered on the forge
# kimb user) — same key, two remotes.
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request

# repo -> {github, forge, key_env}. `github` is the clone source + the nix-fetch
# canonical; `forge` is the PR review surface (ssh://...:2222/kimb/<repo>). The
# scribe authenticates to BOTH with ONE key (BRIDGE_SCRIBE_DEPLOY_KEY) that is
# registered as a mccartykim ACCOUNT SSH key on github (titled "bridge-scribe
# service", NOT a per-repo deploy key — write access to every mccartykim/* repo,
# no per-repo registration) AND registered on the forge kimb user (key id 1).
# The per-repo SCOPE is this allowlist, not the key. The key PATH comes from env
# (set by the shell wrapper, which bakes the agenix /run/agenix path). The
# Chirurgeon (#62) + Interrogator (#53) author their own seed repos for
# structural self-edits (routine tweaks persist in-cycle via org-merge; only the
# immutable head / bin / flake go through this PR loop). Add repos here as
# officers gain scope (#64).
REPOS = {
    "systems-flake": {
        "github": "git@github.com:mccartykim/systems-flake.git",
        # forge SSH user is `forgejo` (the NixOS RUN_USER), NOT `git` —
        # Forgejo's built-in SSH server authenticates by key but keys the
        # connection to RUN_USER; `git@` is rejected "Permission denied
        # (publickey)" despite the key being registered. See vox-organism notes.
        "forge": "ssh://forgejo@10.100.0.10:2222/kimb/systems-flake.git",
        "key_env": "BRIDGE_SCRIBE_DEPLOY_KEY",
    },
    "chirurgeon_organism": {
        "github": "git@github.com:mccartykim/chirurgeon_organism.git",
        "forge": "ssh://forgejo@10.100.0.10:2222/kimb/chirurgeon_organism.git",
        "key_env": "BRIDGE_SCRIBE_DEPLOY_KEY",
    },
    "interrogator_organism": {
        "github": "git@github.com:mccartykim/interrogator_organism.git",
        "forge": "ssh://forgejo@10.100.0.10:2222/kimb/interrogator_organism.git",
        "key_env": "BRIDGE_SCRIBE_DEPLOY_KEY",
    },
    # The Remembrancer (writer officer) authors prose across its own seed
    # repo (structural self-edits) + the two prose repos. The shared
    # BRIDGE_SCRIBE_DEPLOY_KEY (mccartykim account key) already auths to every
    # mccartykim/* repo — NO new key registration. The excluded prose repos
    # (fiction, commonplace_book, writerdeck_builder, borges_book_warehouse,
    # broken_mist_blog) are deliberately absent — OFFICER_REPOS default-denies
    # them; the persona declines by name.
    "remembrancer_organism": {
        "github": "git@github.com:mccartykim/remembrancer_organism.git",
        "forge": "ssh://forgejo@10.100.0.10:2222/kimb/remembrancer_organism.git",
        "key_env": "BRIDGE_SCRIBE_DEPLOY_KEY",
    },
    "kimb-blog-content": {
        "github": "git@github.com:mccartykim/kimb-blog-content.git",
        "forge": "ssh://forgejo@10.100.0.10:2222/kimb/kimb-blog-content.git",
        "key_env": "BRIDGE_SCRIBE_DEPLOY_KEY",
    },
    "mist-blog": {
        "github": "git@github.com:mccartykim/mist-blog.git",
        "forge": "ssh://forgejo@10.100.0.10:2222/kimb/mist-blog.git",
        "key_env": "BRIDGE_SCRIBE_DEPLOY_KEY",
    },
}

FORGE_URL_DEFAULT = "http://10.100.0.10:3000"


def die(msg, code=1):
    sys.stderr.write("bridge-scribe: " + msg + "\n")
    sys.exit(code)


def run(args, env=None):
    return subprocess.run(args, check=True, env=env,
                           capture_output=True, text=True)


def run_soft(args, env=None):
    # Like run() but never raises: returns the CompletedProcess. Used for the
    # github->forge catch-up push, which is EXPECTED to be non-fast-forward
    # (and thus rejected) when the forge is ahead (a PR merged on forge but not
    # yet synced to github). A rejection there is not an error — we fall back to
    # branching off forge/main, which already has that merge.
    return subprocess.run(args, env=env, capture_output=True, text=True)


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


def open_forge_pr(repo, branch, commit_msg, forge_url, token_file):
    # POST /api/v1/repos/kimb/<repo>/pulls -> {html_url}. Token read from
    # token_file (never logged). Returns the PR html_url string. Raises on any
    # failure (caller maps to exit 5); the error message never includes the
    # token.
    if not token_file or not os.path.isfile(token_file):
        raise RuntimeError("forge token not staged (FORGE_TOKEN_FILE)")
    with open(token_file, "r") as fh:
        token = fh.read().strip()
    if not token:
        raise RuntimeError("forge token file is empty")
    body = json.dumps({
        "title": commit_msg,
        "head": branch,
        "base": "main",
    }).encode("utf-8")
    url = forge_url.rstrip("/") + "/api/v1/repos/kimb/" + repo + "/pulls"
    req = urllib.request.Request(
        url, data=body, method="POST",
        headers={
            "Authorization": "token " + token,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:300]
        raise RuntimeError("forge PR API HTTP " + str(e.code) + ": " + detail)
    except Exception as e:
        raise RuntimeError("forge PR API error: " + str(e))
    html_url = data.get("html_url")
    if not html_url:
        raise RuntimeError("forge PR API returned no html_url: " + str(data)[:300])
    return html_url


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

    github = REPOS[repo]["github"]
    forge = REPOS[repo]["forge"]
    git_env = dict(os.environ)
    # One GIT_SSH_COMMAND works for both remotes: -i the shared key,
    # IdentitiesOnly so the agent never substitutes another, accept-new so the
    # forge host key is auto-trusted on first contact (Nebula-only, pinned IP).
    git_env["GIT_SSH_COMMAND"] = (
        "ssh -i " + key_path +
        " -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" +
        " -o BatchMode=yes"
    )

    scratch = tempfile.mkdtemp(prefix="scribe-",
                               dir="/var/lib/bridge-scribe/scratch")
    try:
        # Clone github (full, not --depth 1: a shallow clone can reject the
        # push of a new branch on some servers). github is the current-main
        # source + the nix-fetch canonical; the forge is the PR surface.
        run(["git", "clone", github, scratch], env=git_env)
        os.chdir(scratch)
        run(["git", "remote", "add", "forge", forge], env=git_env)
        # Catch the forge up to github: push every github head -> forge,
        # fast-forward only (no --force). Rejected (non-ff) when the forge is
        # ahead (a merge not yet synced to github) — that's fine; we branch off
        # forge/main below, which already has that merge.
        run_soft(["git", "push", "forge", "refs/heads/*:refs/heads/*"],
                 env=git_env)
        # Pull the forge's current heads (including any forge-ahead merges) so
        # the PR base is max(github, forge), not a stale github snapshot.
        run(["git", "fetch", "forge"], env=git_env)
        # Base the proposal on forge/main if it exists (it does — seeded), else
        # fall back to the cloned github main.
        base_check = run_soft(["git", "rev-parse", "--verify",
                               "refs/remotes/forge/main"], env=git_env)
        base = "refs/remotes/forge/main" if base_check.returncode == 0 else "main"
        run(["git", "checkout", "-b", branch, base], env=git_env)
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
        # honors the standing "no --force on any VCS op" rule. Push to the
        # FORGE now (github gets the merge later via bridge-sync).
        run(["git", "push", "forge", "HEAD:refs/heads/" + branch],
            env=git_env)
        forge_url = os.environ.get("FORGE_URL") or FORGE_URL_DEFAULT
        token_file = os.environ.get("FORGE_TOKEN_FILE")
        pr_url = open_forge_pr(repo, branch, commit_msg, forge_url, token_file)
        sys.stdout.write(pr_url + "\n")
    except subprocess.CalledProcessError as e:
        stderr = (e.stderr or "").strip()
        if len(stderr) > 600:
            stderr = stderr[:600]
        die("git op failed (" + str(e) + "): " + stderr, 5)
    except RuntimeError as e:
        die(str(e), 5)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    main()