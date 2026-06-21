"""SRE Agent PR Worker — reads GitHub issues, drafts fixes, creates PRs.

Polls mccartykim/homelab-incidents for open sre-agent issues, uses Ollama
with tool dispatch to analyze the issue and draft a NixOS config fix in a
temporary clone of the source repo, then creates a branch and opens a PR via gh.

The PR worker does NOT build — that's for CI to validate.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
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


def build_claude_prompt(issue: GitHubIssue) -> str:
    """Build the prompt for Claude Code CLI to fix the issue."""
    source_repo = _env("GITHUB_SOURCE_REPO", "mccartykim/systems-flake")
    return f"""You are an SRE fix agent for a NixOS homelab. A monitoring alert has been filed as a GitHub issue.

## Issue #{issue.number}: {issue.title}

{issue.body}

## Your task

1. Explore the repository structure to understand the codebase.
2. Identify which host(s) and config file(s) are relevant to this alert.
3. Make the MINIMAL config change needed to fix the issue. Do NOT create new host directories. Do NOT make unrelated changes.
4. Valid hosts are listed in the hosts/ directory. Only modify files that already exist.
5. All config must be valid NixOS module syntax (Nix language, NOT Python/JSON).
6. Commit your changes with message: "fix: resolve issue #{issue.number} - {issue.title}"
7. Push to branch "sre-fix/issue-{issue.number}" and create a PR against main on {source_repo}.
8. If the issue cannot be fixed with a config change (requires SSH, hardware fix, manual intervention), say so and do NOT create a PR.

## Important

- Use `gh` for all GitHub operations (it is already authenticated via GH_TOKEN).
- Use `git` for version control operations.
- The PR body should reference issue #{issue.number} and include "Fixes #{issue.number}".
- Output ONLY the PR URL as your final line if a PR was created, or "SKIP: <reason>" if no PR can fix this."""


def extract_pr_url(output: str) -> Optional[str]:
    """Extract a GitHub PR URL from Claude Code output.

    Looks for https://github.com/owner/repo/pull/N patterns.
    Also handles SKIP responses.
    Returns the PR URL, None if no URL found, or None with stderr message for SKIP.
    """
    skip_match = re.search(r"^SKIP:\s*(.+)$", output, re.MULTILINE)
    if skip_match:
        print(f"pr-worker: Claude determined no fix possible: {skip_match.group(1).strip()}", file=sys.stderr)
        return None

    url_match = re.search(r"https://github\.com/[^/]+/[^/]+/pull/\d+", output)
    if url_match:
        return url_match.group(0)

    return None


def fix_issue_with_ollama(issue: GitHubIssue, token: str) -> Optional[str]:
    """Use Ollama with tool dispatch to analyze an issue, edit config, and create a PR.

    Clones the source repo into a temp workspace, invokes Ollama with the
    issue context, and lets the model explore, edit, commit, and create a PR
    via the bash tool.

    Returns the PR URL on success, None on failure or skip.
    """
    state_dir = _env("STATE_DIR", "/var/lib/sre-agent")
    source_repo = _env("GITHUB_SOURCE_REPO", "mccartykim/systems-flake")
    ollama_host = _env("OLLAMA_HOST", "http://historian.nebula:11434")
    model = _env("PR_WORKER_MODEL", "gemma4:12b")
    max_turns = int(_env("PR_WORKER_MAX_TURNS", "15"))

    workspace = os.path.join(state_dir, "workspaces", f"issue-{issue.number}")

    try:
        # Clean up any previous workspace for this issue
        if os.path.exists(workspace):
            shutil.rmtree(workspace)
        os.makedirs(workspace, exist_ok=True)

        # Shallow clone the source repo
        clone_url = f"https://x-access-token:{token}@github.com/{source_repo}.git"
        clone_result = subprocess.run(
            ["git", "clone", "--depth", "1", clone_url, workspace],
            capture_output=True, text=True, timeout=120,
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        )
        if clone_result.returncode != 0:
            print(f"pr-worker: git clone failed: {clone_result.stderr[:500]}", file=sys.stderr)
            return None

        # Build the prompt
        prompt = build_claude_prompt(issue)

        # Set up environment for git/gh commands (used by bash tool)
        tool_env = {
            **os.environ,
            "GH_TOKEN": token,
            "GIT_AUTHOR_NAME": os.environ.get("GIT_AUTHOR_NAME", "sre-agent"),
            "GIT_AUTHOR_EMAIL": os.environ.get("GIT_AUTHOR_EMAIL", "sre-agent@nebula"),
            "GIT_COMMITTER_NAME": os.environ.get("GIT_COMMITTER_NAME", "sre-agent"),
            "GIT_COMMITTER_EMAIL": os.environ.get("GIT_COMMITTER_EMAIL", "sre-agent@nebula"),
            "GIT_TERMINAL_PROMPT": "0",
        }

        # Run Ollama agent loop with bash tool dispatch
        print(f"pr-worker: running ollama for issue #{issue.number} (model={model})", file=sys.stderr)
        result_text = _run_ollama_agent(
            ollama_host=ollama_host,
            model=model,
            system_prompt=PR_WORKER_SYSTEM_PROMPT,
            user_prompt=prompt,
            max_turns=max_turns,
            workspace=workspace,
            tool_env=tool_env,
        )

        if result_text is None:
            print(f"pr-worker: ollama agent failed for issue #{issue.number}", file=sys.stderr)
            return None

        pr_url = extract_pr_url(result_text)
        if pr_url:
            print(f"pr-worker: created PR for issue #{issue.number}: {pr_url}", file=sys.stderr)
        else:
            print(f"pr-worker: no PR URL found in Ollama output for issue #{issue.number}", file=sys.stderr)
            print(f"pr-worker: ollama output: {result_text[:200]}", file=sys.stderr)

        return pr_url

    except Exception as e:
        print(f"pr-worker: fix_issue_with_ollama failed: {e}", file=sys.stderr)
        return None
    finally:
        # Always clean up workspace
        if os.path.exists(workspace):
            try:
                shutil.rmtree(workspace)
            except OSError:
                pass


# System prompt for the PR worker agent
PR_WORKER_SYSTEM_PROMPT = """You are an SRE fix agent for a NixOS homelab. You have access to a bash tool to explore the repository, edit files, run git commands, and create PRs.

When you receive an issue:
1. Use bash to explore the repository structure (ls, find, cat).
2. Identify which host(s) and config file(s) are relevant.
3. Use bash to make the MINIMAL config change needed. Do NOT create new host directories. Do NOT make unrelated changes.
4. All config must be valid NixOS module syntax (Nix language, NOT Python/JSON).
5. Use bash to commit changes: git add, git commit -m "fix: resolve issue #N - TITLE"
6. Use bash to push and create a PR: git push origin HEAD:sre-fix/issue-N, then gh pr create.
7. If the issue cannot be fixed with a config change, respond with SKIP: <reason>.

Important:
- Use `gh` for all GitHub operations (it is already authenticated via GH_TOKEN).
- Use `git` for version control operations.
- The PR body should reference the issue number and include "Fixes #N".
- Output ONLY the PR URL as your final line if a PR was created, or "SKIP: <reason>" if no PR can fix this."""


# Tool definitions for the PR worker agent
PR_WORKER_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "bash",
            "description": "Execute a shell command. Use for exploring files, editing configs, git operations, and gh CLI commands. Commands run in the workspace directory.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "Shell command to execute",
                    },
                },
                "required": ["command"],
            },
        },
    },
]


def _call_ollama(host: str, model: str, messages: list, tools: list = None) -> dict:
    """Call Ollama /api/chat and return the response dict."""
    # think=False is REQUIRED: thinking-capable models (gemma4, qwen3.5,
    # kimi-k2) otherwise spend the entire num_predict budget on thinking
    # tokens and return an empty message.content.
    payload = {
        "model": model,
        "stream": False,
        "think": False,
        "messages": messages,
        "options": {
            "temperature": 0.3,  # Lower temperature for precise config edits
            "num_ctx": int(_env("PR_WORKER_NUM_CTX", "32768")),
            "num_predict": 8192,
        },
    }
    if tools:
        payload["tools"] = tools

    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{host}/api/chat",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    timeout = int(_env("PR_WORKER_OLLAMA_TIMEOUT", "600"))
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def _run_ollama_agent(ollama_host: str, model: str, system_prompt: str,
                      user_prompt: str, max_turns: int = 15,
                      workspace: str = None,
                      tool_env: dict = None) -> Optional[str]:
    """Run the Ollama agent loop with bash tool dispatch.

    Returns the final text response, or None if failed.
    """
    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt},
    ]

    for turn in range(max_turns):
        try:
            response = _call_ollama(ollama_host, model, messages, tools=PR_WORKER_TOOLS)
        except (urllib.error.URLError, urllib.error.HTTPError, ConnectionError, OSError) as e:
            print(f"pr-worker: ollama error on turn {turn}: {e}", file=sys.stderr)
            return None
        except Exception as e:
            print(f"pr-worker: unexpected ollama error on turn {turn}: {e}", file=sys.stderr)
            return None

        message = response.get("message", {})
        tool_calls = message.get("tool_calls", [])

        if not tool_calls:
            # No tool calls — final text response
            content = message.get("content", "")
            return content

        # Add assistant message to history
        messages.append(message)

        # Execute each tool call
        for tc_data in tool_calls:
            fn_name = tc_data.get("function", {}).get("name", "")
            fn_args_str = tc_data.get("function", {}).get("arguments", "{}")
            try:
                fn_args = json.loads(fn_args_str) if isinstance(fn_args_str, str) else fn_args_str
            except json.JSONDecodeError:
                fn_args = {}

            if fn_name != "bash":
                messages.append({
                    "role": "tool",
                    "name": fn_name,
                    "content": f"Error: Unknown tool '{fn_name}'. Only 'bash' is available.",
                })
                continue

            command = fn_args.get("command", "")
            print(f"  bash: {command[:120]}{'...' if len(command) > 120 else ''}", file=sys.stderr)

            try:
                result = subprocess.run(
                    command, shell=True, capture_output=True, text=True,
                    timeout=120, cwd=workspace, env=tool_env,
                )
                output = result.stdout
                if result.stderr:
                    output += f"\n(stderr: {result.stderr[:500]})"
                if result.returncode != 0:
                    output += f"\n(exit code {result.returncode})"
            except subprocess.TimeoutExpired:
                output = "Error: Command timed out (120s)"
            except Exception as e:
                output = f"Error executing command: {e}"

            # Truncate very long outputs
            if len(output) > 12000:
                output = output[:12000] + "\n... (truncated)"

            messages.append({
                "role": "tool",
                "name": fn_name,
                "content": output,
            })

    # Max turns reached — get final response without tools
    print(f"pr-worker: max turns ({max_turns}) reached, requesting final response", file=sys.stderr)
    try:
        final_response = _call_ollama(ollama_host, model, messages, tools=None)
        return final_response.get("message", {}).get("content", "")
    except Exception as e:
        print(f"pr-worker: ollama final response error: {e}", file=sys.stderr)
        return None


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

        pr_url = fix_issue_with_ollama(issue, token)
        if pr_url:
            mark_issue_created(issue.number, pr_url, token)
            prs_created += 1
        else:
            print(f"pr-worker: no PR created for issue #{issue.number}", file=sys.stderr)

    _write_last_run(state_dir, prs_created, len(issues))


if __name__ == "__main__":
    run_pr_worker()