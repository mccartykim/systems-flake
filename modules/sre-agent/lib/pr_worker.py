"""SRE Agent PR Worker — reads GitHub issues, drafts fixes, creates PRs.

Polls mccartykim/homelab-incidents for open sre-agent issues, uses an LLM
to analyze the issue and draft a NixOS config fix, then creates a branch
and opens a PR on the source repo (mccartykim/systems-flake).

The PR worker does NOT build — that's for CI to validate.
"""
import json
import os
import sys
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional


def _env(key, default=""):
    return os.environ.get(key, default)


@dataclass
class GitHubIssue:
    number: int
    title: str
    body: str
    labels: list
    url: str


@dataclass
class PRDraft:
    title: str
    body: str
    branch: str
    files: list  # [{"path": "...", "content": "..."}]


# Known hosts in the systems-flake repo (from hosts/ directory)
KNOWN_HOSTS = [
    "bartleby", "cheesecake", "donut", "historian", "maitred",
    "marshmallow", "mochi", "oracle", "rich-evans", "total-eclipse",
]

# Common config file patterns per host
HOST_CONFIG_FILES = [
    "configuration.nix", "hardware-configuration.nix", "networking.nix",
    "services.nix", "monitoring.nix", "monitoring-probes.nix",
]


def _github_api(path, token, method="GET", data=None):
    """Make a GitHub API request to the source repo. Returns parsed JSON or None."""
    repo = _env("GITHUB_SOURCE_REPO", "mccartykim/systems-flake")
    url = f"https://api.github.com/repos/{repo}/{path}"
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "sre-agent/1.0",
    }
    payload = None
    if data is not None:
        payload = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=payload, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(f"pr-worker: github api error {e.code} on {method} {path}: {e.reason}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"pr-worker: github api failure: {e}", file=sys.stderr)
        return None


def _incident_api(path, token, method="GET", data=None):
    """Make a GitHub API request to the incidents repo."""
    repo = _env("GITHUB_REPO", "mccartykim/homelab-incidents")
    url = f"https://api.github.com/repos/{repo}/{path}"
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "sre-agent/1.0",
    }
    payload = None
    if data is not None:
        payload = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=payload, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(f"pr-worker: incident api error {e.code} on {method} {path}: {e.reason}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"pr-worker: incident api failure: {e}", file=sys.stderr)
        return None


def get_repo_tree(token, max_depth=2):
    """Fetch the file tree from the source repo for LLM context.

    Returns a list of file paths (truncated to max_depth depth) for prompt context.
    """
    data = _github_api("git/trees/main?recursive=1", token)
    if not data or "tree" not in data:
        return []
    paths = []
    for item in data["tree"]:
        p = item["path"]
        # Skip deep paths and hidden dirs
        depth = p.count("/")
        if depth > max_depth:
            continue
        if any(s in p for s in [".git", "secrets/", ".github/"]):
            continue
        if item["type"] == "blob":
            paths.append(p)
    return paths


def list_open_issues(token):
    """List open issues with sre-agent label from the incidents repo."""
    data = _incident_api("issues?labels=sre-agent&state=open", token)
    if not data:
        return []
    issues = []
    for item in data:
        if isinstance(item, dict) and "pull_request" not in item:
            issues.append(GitHubIssue(
                number=item["number"],
                title=item.get("title", ""),
                body=item.get("body", "") or "",
                labels=[l["name"] for l in item.get("labels", [])],
                url=item.get("html_url", ""),
            ))
    return issues


def build_fix_prompt(issue: GitHubIssue, repo_paths=None):
    """Build an LLM prompt for drafting a NixOS config fix."""
    # Determine which host is relevant from the issue title/body
    host_hint = ""
    for host in KNOWN_HOSTS:
        if host in issue.title.lower() or host in issue.body.lower():
            host_hint = f"\nThe alert is about host '{host}'. Relevant files are in hosts/{host}/."
            break

    # Build repo context section
    repo_context = ""
    if repo_paths:
        # Filter to paths likely relevant to the issue
        relevant = []
        for p in repo_paths:
            # Always include module definitions and host configs
            if p.startswith("modules/") or p.startswith("hosts/") or p.startswith("flake.nix"):
                relevant.append(p)
        if relevant:
            repo_context = "\n\nRepository file structure (relevant paths):\n" + "\n".join(f"  {p}" for p in relevant[:80])

    return f"""You are an SRE fix agent for a NixOS homelab. Given this GitHub issue, draft a fix.

Issue #{issue.number}: {issue.title}

{issue.body}
{host_hint}
{repo_context}

IMPORTANT RULES:
- Only modify files that ALREADY EXIST in the repository. Do NOT create new host directories.
- Valid hosts: {', '.join(KNOWN_HOSTS)}. File paths must use one of these host names.
- All config must be valid NixOS module syntax (Nix language, NOT Python/JSON).
- Only change what's necessary to fix the issue.
- If you cannot fix this with a config change (e.g., requires SSH, hardware fix, manual intervention), respond with skip.

Respond in this exact JSON format:
{{
  "title": "fix(hostname): short description",
  "branch": "sre-fix/issue-{issue.number}",
  "summary": "One-line summary of the fix for the PR body",
  "files": [
    {{
      "path": "hosts/hostname/some-config.nix",
      "description": "What this change does",
      "content": "The FULL file content with the fix applied"
    }}
  ]
}}

If the issue cannot be fixed with a config change, respond with:
{{"skip": true, "reason": "explanation of why no PR can fix this"}}"""


def draft_fix_with_llm(issue: GitHubIssue, repo_paths=None, model=None):
    """Use cloud LLM to draft a fix for the issue. Returns PRDraft or None.

    Uses a large coding-capable model (gemma4:31b on historian) via Ollama Cloud
    rather than the small local model, since PR fixes need better code generation.
    """
    prompt = build_fix_prompt(issue, repo_paths)

    cloud_host = os.environ.get("PR_WORKER_CLOUD_HOST", "http://historian.nebula:11434")
    cloud_model = model or os.environ.get("PR_WORKER_MODEL", "gemma4:31b")
    key_file = os.environ.get("OLLAMA_CLOUD_KEY_FILE", "")

    url = f"{cloud_host}/api/chat"
    headers = {"Content-Type": "application/json", "User-Agent": "sre-agent/1.0"}
    if key_file and os.path.exists(key_file):
        try:
            with open(key_file) as f:
                key = f.read().strip()
            if key and not key.startswith("PLACEHOLDER"):
                headers["Authorization"] = f"Bearer {key}"
        except OSError:
            pass

    for attempt in range(2):
        try:
            payload = json.dumps({
                "model": cloud_model,
                "messages": [
                    {"role": "system", "content": "You are an SRE fix agent for a NixOS homelab. Draft minimal, targeted config fixes. Only output valid JSON."},
                    {"role": "user", "content": prompt},
                ],
                "stream": False,
                "format": "json",
                "options": {"temperature": 0.2},
            }).encode()
            req = urllib.request.Request(url, data=payload, headers=headers)
            resp = urllib.request.urlopen(req, timeout=300)
            body = json.loads(resp.read().decode())
            content = body.get("message", {}).get("content", "")
            try:
                parsed = json.loads(content)
            except json.JSONDecodeError:
                print(f"pr-worker: cloud LLM returned invalid JSON (attempt {attempt+1}): {content[:200]}", file=sys.stderr)
                continue
            if parsed and not parsed.get("skip"):
                return PRDraft(
                    title=parsed.get("title", f"[SRE] Fix issue #{issue.number}"),
                    body=parsed.get("summary", ""),
                    branch=parsed.get("branch", f"sre-fix/issue-{issue.number}"),
                    files=parsed.get("files", []),
                )
            elif parsed and parsed.get("skip"):
                print(f"pr-worker: skipping issue #{issue.number}: {parsed.get('reason', 'no fix possible')}", file=sys.stderr)
                return None
        except Exception as e:
            print(f"pr-worker: cloud LLM failed (attempt {attempt+1}): {e}", file=sys.stderr)
            continue

    return None


def create_pr(draft: PRDraft, token):
    """Create a branch and open a PR on the source repo using the Git Data API.

    Uses the Git Data API (blobs, trees, commits) to create changes without
    cloning the repo. Pure API, no local git needed.
    """
    repo = _env("GITHUB_SOURCE_REPO", "mccartykim/systems-flake")

    # 1. Get the main branch SHA
    ref = _github_api("git/ref/heads/main", token)
    if not ref:
        print("pr-worker: failed to get main branch ref", file=sys.stderr)
        return None
    main_sha = ref["object"]["sha"]

    # 2. Get the tree SHA of the latest commit on main
    commit = _github_api(f"git/commits/{main_sha}", token)
    if not commit:
        print("pr-worker: failed to get main commit", file=sys.stderr)
        return None
    base_tree_sha = commit["tree"]["sha"]

    # 3. Create a new branch from main
    branch_ref = _github_api("git/refs", token, method="POST", data={
        "ref": f"refs/heads/{draft.branch}",
        "sha": main_sha,
    })
    if not branch_ref:
        print(f"pr-worker: failed to create branch {draft.branch}", file=sys.stderr)
        return None

    # 4. Create blobs for each file
    tree_items = []
    for f in draft.files:
        blob = _github_api("git/blobs", token, method="POST", data={
            "content": f["content"],
            "encoding": "utf-8",
        })
        if not blob:
            print(f"pr-worker: failed to create blob for {f['path']}", file=sys.stderr)
            continue
        tree_items.append({
            "path": f["path"],
            "mode": "100644",
            "type": "blob",
            "sha": blob["sha"],
        })

    if not tree_items:
        print("pr-worker: no files to commit", file=sys.stderr)
        return None

    # 5. Create a new tree with the file changes
    new_tree = _github_api("git/trees", token, method="POST", data={
        "base_tree": base_tree_sha,
        "tree": tree_items,
    })
    if not new_tree:
        print("pr-worker: failed to create tree", file=sys.stderr)
        return None

    # 6. Create a commit
    new_commit = _github_api("git/commits", token, method="POST", data={
        "message": draft.title,
        "tree": new_tree["sha"],
        "parents": [main_sha],
    })
    if not new_commit:
        print("pr-worker: failed to create commit", file=sys.stderr)
        return None

    # 7. Update the branch to point to the new commit
    _github_api(f"git/refs/heads/{draft.branch}", token, method="PATCH", data={
        "sha": new_commit["sha"],
    })

    # 8. Create the pull request
    pr = _github_api("pulls", token, method="POST", data={
        "title": draft.title,
        "body": f"{draft.body}\n\nFixes #{draft.branch.split('-')[-1] if '-' in draft.branch else ''}\n\n🤖 Generated by sre-agent",
        "head": draft.branch,
        "base": "main",
    })
    if not pr:
        print("pr-worker: failed to create PR", file=sys.stderr)
        return None

    return pr.get("html_url")


def mark_issue_processing(issue_number: int, token):
    """Add a 'pr-processing' label to the issue so we don't pick it up again."""
    _incident_api(f"issues/{issue_number}/labels", token, method="POST", data={
        "labels": ["pr-processing"],
    })


def mark_issue_created(issue_number: int, pr_url: str, token):
    """Add a 'pr-created' label and comment with the PR link on the issue."""
    _incident_api(f"issues/{issue_number}/labels", token, method="POST", data={
        "labels": ["pr-created"],
    })
    _incident_api(f"issues/{issue_number}/comments", token, method="POST", data={
        "body": f"PR created: {pr_url}\n🤖 This PR was automatically generated by sre-agent.",
    })


def is_issue_processed(issue_number: int, token):
    """Check if an issue already has the pr-processing or pr-created label."""
    data = _incident_api(f"issues/{issue_number}", token)
    if not data:
        return False
    labels = [l["name"] for l in data.get("labels", [])]
    return "pr-processing" in labels or "pr-created" in labels


def _read_last_run(state_dir: str) -> Optional[dict]:
    """Read the last run state file for debounce."""
    path = os.path.join(state_dir, "pr-worker-state.json")
    if not os.path.exists(path):
        return None
    try:
        with open(path) as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return None


def _write_last_run(state_dir: str, prs_created: int, issue_count: int):
    """Write the last run state for debounce."""
    path = os.path.join(state_dir, "pr-worker-state.json")
    try:
        entry = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "prs_created": prs_created,
            "issue_count": issue_count,
        }
        with open(path, "w") as f:
            json.dump(entry, f)
    except OSError:
        pass


MAX_PRS_PER_RUN = 3
MIN_RUN_INTERVAL_SECONDS = 300  # 5 minutes minimum between runs that create PRs


def run_pr_worker():
    """Main entry point: poll for issues, draft fixes, create PRs.

    Debounce: skips run if last PR-creating run was less than MIN_RUN_INTERVAL_SECONDS ago.
    Rate limit: creates at most MAX_PRS_PER_RUN PRs per run.
    """
    state_dir = _env("STATE_DIR", "/var/lib/sre-agent")
    max_prs = int(_env("MAX_PRS_PER_RUN", str(MAX_PRS_PER_RUN)))

    token_file = _env("GITHUB_TOKEN_FILE", "")
    if not token_file or not os.path.exists(token_file):
        print("pr-worker: no GitHub token configured", file=sys.stderr)
        return

    try:
        with open(token_file) as f:
            token = f.read().strip()
    except OSError:
        print("pr-worker: cannot read GitHub token", file=sys.stderr)
        return

    if not token or token.startswith("PLACEHOLDER"):
        print("pr-worker: token is placeholder", file=sys.stderr)
        return

    # Debounce: skip if last PR-creating run was too recent
    last_run = _read_last_run(state_dir)
    if last_run and last_run.get("prs_created", 0) > 0:
        try:
            last_ts = datetime.fromisoformat(last_run["ts"])
            elapsed = (datetime.now(timezone.utc) - last_ts).total_seconds()
            if elapsed < MIN_RUN_INTERVAL_SECONDS:
                print(f"pr-worker: last PR-creating run was {int(elapsed)}s ago, debouncing (min {MIN_RUN_INTERVAL_SECONDS}s)", file=sys.stderr)
                return
        except (KeyError, ValueError):
            pass

    issues = list_open_issues(token)
    print(f"pr-worker: found {len(issues)} open sre-agent issues", file=sys.stderr)

    if not issues:
        _write_last_run(state_dir, 0, 0)
        return

    # Fetch repo tree for LLM context (only if there are issues to process)
    repo_paths = get_repo_tree(token)

    prs_created = 0
    for issue in issues:
        if prs_created >= max_prs:
            print(f"pr-worker: hit max PRs per run ({max_prs}), stopping", file=sys.stderr)
            break

        if is_issue_processed(issue.number, token):
            print(f"pr-worker: issue #{issue.number} already processed, skipping", file=sys.stderr)
            continue

        print(f"pr-worker: processing issue #{issue.number}: {issue.title}", file=sys.stderr)
        mark_issue_processing(issue.number, token)

        draft = draft_fix_with_llm(issue, repo_paths=repo_paths)
        if not draft or not draft.files:
            print(f"pr-worker: no fix draft for issue #{issue.number}", file=sys.stderr)
            continue

        pr_url = create_pr(draft, token)
        if pr_url:
            mark_issue_created(issue.number, pr_url, token)
            prs_created += 1
            print(f"pr-worker: created PR for issue #{issue.number}: {pr_url}", file=sys.stderr)
        else:
            print(f"pr-worker: failed to create PR for issue #{issue.number}", file=sys.stderr)

    _write_last_run(state_dir, prs_created, len(issues))


if __name__ == "__main__":
    run_pr_worker()