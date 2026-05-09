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


def _github_api(path, token, method="GET", data=None):
    """Make a GitHub API request. Returns parsed JSON or None on failure."""
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


def build_fix_prompt(issue: GitHubIssue):
    """Build an LLM prompt for drafting a NixOS config fix."""
    return f"""You are an SRE fix agent for a NixOS homelab. Given this GitHub issue, draft a fix.

Issue #{issue.number}: {issue.title}

{issue.body}

The fix should modify files in the systems-flake repository (NixOS configurations).
Only change what's necessary. Explain your reasoning briefly.

Respond in this exact JSON format:
{{
  "title": "fix(hostname): short description",
  "branch": "sre-fix/issue-{issue.number}",
  "summary": "One-line summary of the fix for the PR body",
  "files": [
    {{
      "path": "hosts/hostname/filename.nix",
      "description": "What this change does",
      "content": "The full file content or a diff-like description of changes"
    }}
  ]
}}

If the issue cannot be fixed with a config change (e.g., requires SSH into a host, hardware fix, or manual intervention), respond with:
{{"skip": true, "reason": "explanation of why no PR can fix this"}}"""


def draft_fix_with_llm(issue: GitHubIssue, model=None):
    """Use LLM to draft a fix for the issue. Returns PRDraft or None."""
    from llm_client import _call_local_ollama, _call_cloud_ollama, parse_freeform_response

    prompt = build_fix_prompt(issue)

    # Try local Ollama first, then cloud fallback
    result = None
    for attempt in range(2):
        try:
            url = f"{os.environ.get('OLLAMA_HOST', 'http://total-eclipse.nebula:11434')}/api/chat"
            payload = json.dumps({
                "model": model or os.environ.get("PR_WORKER_MODEL", os.environ.get("OLLAMA_MODEL", "qwen3:8b")),
                "messages": [
                    {"role": "system", "content": "You are an SRE fix agent for a NixOS homelab. Draft minimal, targeted config fixes."},
                    {"role": "user", "content": prompt},
                ],
                "stream": False,
                "format": "json",
                "options": {"temperature": 0.2},
            }).encode()
            req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json", "User-Agent": "sre-agent/1.0"})
            resp = urllib.request.urlopen(req, timeout=120)
            body = json.loads(resp.read().decode())
            content = body.get("message", {}).get("content", "")
            try:
                parsed = json.loads(content)
            except json.JSONDecodeError:
                # Try free-form parsing as fallback
                parsed = None
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
            # If parsing failed, try cloud fallback
            break
        except Exception as e:
            print(f"pr-worker: local LLM failed (attempt {attempt+1}): {e}", file=sys.stderr)
            continue

    # Cloud fallback
    try:
        result = _call_cloud_ollama(prompt)
        if result:
            # cloud returns free-form, parse it
            # For PR worker, we need JSON, so just try to extract from the response
            pass
    except Exception as e:
        print(f"pr-worker: cloud LLM failed: {e}", file=sys.stderr)

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


def is_issue_processed(issue_number: int, token):
    """Check if an issue already has the pr-processing label."""
    data = _incident_api(f"issues/{issue_number}", token)
    if not data:
        return False
    labels = [l["name"] for l in data.get("labels", [])]
    return "pr-processing" in labels or "pr-created" in labels


def run_pr_worker():
    """Main entry point: poll for issues, draft fixes, create PRs."""
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

    issues = list_open_issues(token)
    print(f"pr-worker: found {len(issues)} open sre-agent issues", file=sys.stderr)

    for issue in issues:
        if is_issue_processed(issue.number, token):
            print(f"pr-worker: issue #{issue.number} already processed, skipping", file=sys.stderr)
            continue

        print(f"pr-worker: processing issue #{issue.number}: {issue.title}", file=sys.stderr)
        mark_issue_processing(issue.number, token)

        draft = draft_fix_with_llm(issue)
        if not draft or not draft.files:
            print(f"pr-worker: no fix draft for issue #{issue.number}", file=sys.stderr)
            continue

        pr_url = create_pr(draft, token)
        if pr_url:
            print(f"pr-worker: created PR for issue #{issue.number}: {pr_url}", file=sys.stderr)
        else:
            print(f"pr-worker: failed to create PR for issue #{issue.number}", file=sys.stderr)


if __name__ == "__main__":
    run_pr_worker()