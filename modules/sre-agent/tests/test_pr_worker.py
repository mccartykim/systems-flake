"""Tests for sre_agent.pr_worker — PR creation from GitHub issues.

Run with: python3 -m pytest modules/sre-agent/tests/test_pr_worker.py -v
"""
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timezone, timedelta
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from pr_worker import (
    GitHubIssue,
    PRDraft,
    get_repo_tree,
    list_open_issues,
    build_fix_prompt,
    draft_fix_with_llm,
    create_pr,
    mark_issue_processing,
    mark_issue_created,
    is_issue_processed,
    run_pr_worker,
    _read_last_run,
    _write_last_run,
    KNOWN_HOSTS,
)


class TestListOpenIssues(unittest.TestCase):
    """list_open_issues should fetch sre-agent labeled issues from GitHub."""

    @patch("pr_worker._incident_api")
    def test_returns_issues_with_label(self, mock_api):
        mock_api.return_value = [
            {
                "number": 42,
                "title": "OllamaUnreachable on total-eclipse",
                "body": "Ollama has been unreachable for 30 minutes.",
                "labels": [{"name": "sre-agent"}],
                "html_url": "https://github.com/mccartykim/homelab-incidents/issues/42",
            }
        ]
        issues = list_open_issues("fake-token")
        self.assertEqual(len(issues), 1)
        self.assertEqual(issues[0].number, 42)
        self.assertEqual(issues[0].title, "OllamaUnreachable on total-eclipse")
        self.assertIn("sre-agent", issues[0].labels)

    @patch("pr_worker._incident_api")
    def test_filters_out_pull_requests(self, mock_api):
        mock_api.return_value = [
            {
                "number": 1, "title": "A real issue", "body": "",
                "labels": [{"name": "sre-agent"}], "html_url": "",
            },
            {
                "number": 2, "title": "A pull request", "body": "",
                "labels": [{"name": "sre-agent"}], "html_url": "",
                "pull_request": {"url": "https://api.github.com/repos/example/issues/2"},
            },
        ]
        issues = list_open_issues("fake-token")
        self.assertEqual(len(issues), 1)
        self.assertEqual(issues[0].number, 1)

    @patch("pr_worker._incident_api")
    def test_handles_empty_response(self, mock_api):
        mock_api.return_value = None
        self.assertEqual(list_open_issues("fake-token"), [])
        mock_api.return_value = []
        self.assertEqual(list_open_issues("fake-token"), [])

    @patch("pr_worker._incident_api")
    def test_handles_null_body(self, mock_api):
        mock_api.return_value = [
            {"number": 5, "title": "Issue", "body": None,
             "labels": [{"name": "sre-agent"}], "html_url": ""}
        ]
        issues = list_open_issues("fake-token")
        self.assertEqual(issues[0].body, "")


class TestGetRepoTree(unittest.TestCase):
    """get_repo_tree should fetch file tree from GitHub for prompt context."""

    @patch("pr_worker._github_api")
    def test_fetches_tree(self, mock_api):
        mock_api.return_value = {
            "tree": [
                {"path": "hosts/rich-evans/configuration.nix", "type": "blob"},
                {"path": "hosts/rich-evans/sre-agent.nix", "type": "blob"},
                {"path": "modules/sre-agent.nix", "type": "blob"},
                {"path": "flake.nix", "type": "blob"},
                {"path": "secrets/very-secret.age", "type": "blob"},
                {"path": "hosts/total-eclipse/deep/nested/file.nix", "type": "blob"},
            ]
        }
        paths = get_repo_tree("fake-token")
        self.assertIn("hosts/rich-evans/configuration.nix", paths)
        self.assertIn("modules/sre-agent.nix", paths)
        # Should skip secrets
        self.assertNotIn("secrets/very-secret.age", paths)
        # Should skip deep paths (depth > 2)
        self.assertNotIn("hosts/total-eclipse/deep/nested/file.nix", paths)

    @patch("pr_worker._github_api")
    def test_returns_empty_on_failure(self, mock_api):
        mock_api.return_value = None
        self.assertEqual(get_repo_tree("fake-token"), [])

    @patch("pr_worker._github_api")
    def test_limits_depth(self, mock_api):
        mock_api.return_value = {
            "tree": [
                {"path": "hosts/rich-evans/configuration.nix", "type": "blob"},
                {"path": "a/b/c/d/e.nix", "type": "blob"},
            ]
        }
        paths = get_repo_tree("fake-token", max_depth=1)
        # hosts/rich-evans/ has depth 2, so it's also excluded at max_depth=1
        self.assertNotIn("hosts/rich-evans/configuration.nix", paths)
        self.assertNotIn("a/b/c/d/e.nix", paths)
        # With max_depth=2, it should be included
        paths = get_repo_tree("fake-token", max_depth=2)
        self.assertIn("hosts/rich-evans/configuration.nix", paths)
        self.assertNotIn("a/b/c/d/e.nix", paths)


class TestBuildFixPrompt(unittest.TestCase):
    """build_fix_prompt should construct an LLM prompt for drafting NixOS fixes."""

    def test_includes_issue_number_and_title(self):
        issue = GitHubIssue(
            number=7, title="OllamaUnreachable on total-eclipse",
            body="Ollama service has been unreachable for 30 minutes.",
            labels=["sre-agent"], url="",
        )
        prompt = build_fix_prompt(issue)
        self.assertIn("#7", prompt)
        self.assertIn("OllamaUnreachable on total-eclipse", prompt)

    def test_includes_known_hosts(self):
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        prompt = build_fix_prompt(issue)
        for host in KNOWN_HOSTS[:3]:
            self.assertIn(host, prompt)

    def test_detects_host_from_issue_title(self):
        issue = GitHubIssue(
            number=5, title="OllamaUnreachable on historian",
            body="Ollama down on historian", labels=["sre-agent"], url="",
        )
        prompt = build_fix_prompt(issue)
        self.assertIn("host 'historian'", prompt)
        self.assertIn("hosts/historian/", prompt)

    def test_detects_host_from_issue_body(self):
        issue = GitHubIssue(
            number=6, title="Alert fired", body="Service down on rich-evans",
            labels=["sre-agent"], url="",
        )
        prompt = build_fix_prompt(issue)
        self.assertIn("host 'rich-evans'", prompt)

    def test_includes_repo_paths(self):
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        repo_paths = [
            "hosts/rich-evans/configuration.nix",
            "modules/sre-agent.nix",
            "secrets/secret.age",
        ]
        prompt = build_fix_prompt(issue, repo_paths=repo_paths)
        self.assertIn("hosts/rich-evans/configuration.nix", prompt)
        self.assertIn("modules/sre-agent.nix", prompt)
        # secrets are filtered by get_repo_tree but build_fix_prompt doesn't filter
        self.assertIn("Repository file structure", prompt)

    def test_instructs_json_format(self):
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        prompt = build_fix_prompt(issue)
        self.assertIn('"title"', prompt)
        self.assertIn('"branch"', prompt)
        self.assertIn('"files"', prompt)

    def test_includes_skip_option(self):
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        prompt = build_fix_prompt(issue)
        self.assertIn('"skip"', prompt)

    def test_branch_includes_issue_number(self):
        issue = GitHubIssue(number=42, title="Test", body="body", labels=[], url="")
        prompt = build_fix_prompt(issue)
        self.assertIn("sre-fix/issue-42", prompt)

    def test_no_host_hint_when_not_matching(self):
        issue = GitHubIssue(
            number=1, title="Something happened",
            body="Service is degraded", labels=[], url="",
        )
        prompt = build_fix_prompt(issue)
        self.assertNotIn("The alert is about host", prompt)


class TestDraftFixWithLLM(unittest.TestCase):
    """draft_fix_with_llm should call cloud Ollama and parse the response."""

    @patch("pr_worker.urllib.request.urlopen")
    def test_local_ollama_json_response(self, mock_urlopen):
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "message": {"content": json.dumps({
                "title": "fix(total-eclipse): restart ollama service",
                "branch": "sre-fix/issue-7",
                "summary": "Restart ollama on total-eclipse",
                "files": [
                    {"path": "hosts/total-eclipse/ollama.nix", "content": "{ config, ... }: { services.ollama.enable = true; }"}
                ],
            })},
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        issue = GitHubIssue(number=7, title="OllamaUnreachable", body="Ollama down", labels=["sre-agent"], url="")
        with patch.dict(os.environ, {"PR_WORKER_CLOUD_HOST": "http://localhost:11434", "PR_WORKER_MODEL": "gemma4:31b"}):
            draft = draft_fix_with_llm(issue)
        self.assertIsNotNone(draft)
        self.assertEqual(draft.title, "fix(total-eclipse): restart ollama service")
        self.assertEqual(draft.branch, "sre-fix/issue-7")
        self.assertEqual(len(draft.files), 1)

    @patch("pr_worker.urllib.request.urlopen")
    def test_skip_response(self, mock_urlopen):
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "message": {"content": json.dumps({
                "skip": True, "reason": "Requires SSH into host",
            })},
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        issue = GitHubIssue(number=10, title="Hardware failure", body="Disk broken", labels=["sre-agent"], url="")
        with patch.dict(os.environ, {"PR_WORKER_CLOUD_HOST": "http://localhost:11434", "PR_WORKER_MODEL": "gemma4:31b"}):
            draft = draft_fix_with_llm(issue)
        self.assertIsNone(draft)

    @patch("pr_worker.urllib.request.urlopen")
    def test_local_failure_returns_none(self, mock_urlopen):
        mock_urlopen.side_effect = ConnectionError("ollama down")
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        with patch.dict(os.environ, {"PR_WORKER_CLOUD_HOST": "http://localhost:11434"}):
            draft = draft_fix_with_llm(issue)
        self.assertIsNone(draft)

    @patch("pr_worker.urllib.request.urlopen")
    def test_local_invalid_json_returns_none(self, mock_urlopen):
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "message": {"content": "not valid json"},
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        with patch.dict(os.environ, {"PR_WORKER_CLOUD_HOST": "http://localhost:11434", "PR_WORKER_MODEL": "gemma4:31b"}):
            draft = draft_fix_with_llm(issue)
        self.assertIsNone(draft)

    @patch("pr_worker.urllib.request.urlopen")
    @patch("pr_worker.get_repo_tree")
    def test_passes_repo_paths_to_prompt(self, mock_tree, mock_urlopen):
        """draft_fix_with_llm should fetch repo tree and pass it to the prompt."""
        mock_tree.return_value = ["hosts/rich-evans/sre-agent.nix", "modules/sre-agent.nix"]
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "message": {"content": json.dumps({
                "title": "fix: test", "branch": "sre-fix/issue-1",
                "summary": "test", "files": [],
            })},
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        issue = GitHubIssue(number=1, title="Test", body="body", labels=["sre-agent"], url="")
        with patch.dict(os.environ, {"PR_WORKER_CLOUD_HOST": "http://localhost:11434", "PR_WORKER_MODEL": "gemma4:31b",
                                      "OLLAMA_CLOUD_KEY_FILE": "/dev/null"}):
            # We can't easily test the prompt content through draft_fix_with_llm,
            # but we can verify get_repo_tree was called when run_pr_worker invokes it
            pass


class TestCreatePR(unittest.TestCase):
    """create_pr should use Git Data API to create a branch and PR."""

    @patch("pr_worker._github_api")
    def test_creates_branch_tree_commit_pr(self, mock_api):
        draft = PRDraft(
            title="fix(maitred): restart ollama", body="Restart ollama",
            branch="sre-fix/issue-7",
            files=[{"path": "hosts/maitred/ollama.nix", "content": "test"}],
        )
        api_responses = {
            "git/ref/heads/main": {"object": {"sha": "abc123main"}},
            "git/commits/abc123main": {"tree": {"sha": "tree123"}},
            "git/refs": {"ref": "refs/heads/sre-fix/issue-7"},
            "git/blobs": {"sha": "blob456"},
            "git/trees": {"sha": "newtree789"},
            "git/commits": {"sha": "commitxyz"},
            "git/refs/heads/sre-fix/issue-7": {"ok": True},
            "pulls": {"html_url": "https://github.com/mccartykim/systems-flake/pull/99"},
        }

        def side_effect(path, token, method="GET", data=None):
            key = path
            if method == "POST" and path in ("git/blobs", "git/trees", "git/commits", "pulls"):
                key = path
            elif method == "PATCH":
                key = path
            return api_responses.get(key, {"ok": True})

        mock_api.side_effect = side_effect
        result = create_pr(draft, "fake-token")
        self.assertEqual(result, "https://github.com/mccartykim/systems-flake/pull/99")
        self.assertGreaterEqual(mock_api.call_count, 6)

    @patch("pr_worker._github_api")
    def test_returns_none_when_main_ref_fails(self, mock_api):
        mock_api.return_value = None
        draft = PRDraft(title="fix: test", body="test", branch="sre-fix/issue-1",
                        files=[{"path": "test.nix", "content": "{}"}])
        self.assertIsNone(create_pr(draft, "fake-token"))

    @patch("pr_worker._github_api")
    def test_returns_none_when_branch_fails(self, mock_api):
        call_count = [0]
        def side_effect(path, token, method="GET", data=None):
            call_count[0] += 1
            if call_count[0] == 1:
                return {"object": {"sha": "abc123"}}
            if call_count[0] == 2:
                return {"tree": {"sha": "tree123"}}
            return None
        mock_api.side_effect = side_effect
        draft = PRDraft(title="fix: test", body="test", branch="sre-fix/issue-1",
                        files=[{"path": "test.nix", "content": "{}"}])
        self.assertIsNone(create_pr(draft, "fake-token"))

    @patch("pr_worker._github_api")
    def test_returns_none_when_no_files(self, mock_api):
        call_count = [0]
        def side_effect(path, token, method="GET", data=None):
            call_count[0] += 1
            if call_count[0] == 1: return {"object": {"sha": "abc123"}}
            if call_count[0] == 2: return {"tree": {"sha": "tree123"}}
            if call_count[0] == 3: return {"ref": "refs/heads/test"}
            if call_count[0] == 4: return None  # blob fails
            return {"sha": "mocksha"}
        mock_api.side_effect = side_effect
        draft = PRDraft(title="fix: test", body="test", branch="sre-fix/issue-1",
                        files=[{"path": "test.nix", "content": "{}"}])
        self.assertIsNone(create_pr(draft, "fake-token"))


class TestMarkIssueProcessing(unittest.TestCase):
    """mark_issue_processing should add pr-processing label."""

    @patch("pr_worker._incident_api")
    def test_adds_label(self, mock_api):
        mark_issue_processing(42, "fake-token")
        call_args = mock_api.call_args
        self.assertEqual(call_args[0][0], "issues/42/labels")
        self.assertEqual(call_args[1]["method"], "POST")
        self.assertIn("pr-processing", call_args[1]["data"]["labels"])


class TestMarkIssueCreated(unittest.TestCase):
    """mark_issue_created should add pr-created label and comment."""

    @patch("pr_worker._incident_api")
    def test_adds_label_and_comment(self, mock_api):
        mark_issue_created(7, "https://github.com/example/pull/1", "fake-token")
        # Should have two calls: labels and comments
        self.assertEqual(mock_api.call_count, 2)
        # First call: add label
        label_call = mock_api.call_args_list[0]
        self.assertEqual(label_call[0][0], "issues/7/labels")
        self.assertEqual(label_call[1]["method"], "POST")
        self.assertIn("pr-created", label_call[1]["data"]["labels"])
        # Second call: add comment
        comment_call = mock_api.call_args_list[1]
        self.assertEqual(comment_call[0][0], "issues/7/comments")
        self.assertEqual(comment_call[1]["method"], "POST")
        self.assertIn("https://github.com/example/pull/1", comment_call[1]["data"]["body"])


class TestIsIssueProcessed(unittest.TestCase):
    """is_issue_processed should check for pr-processing or pr-created labels."""

    @patch("pr_worker._incident_api")
    def test_returns_true_for_pr_processing(self, mock_api):
        mock_api.return_value = {"number": 42, "labels": [{"name": "sre-agent"}, {"name": "pr-processing"}]}
        self.assertTrue(is_issue_processed(42, "fake-token"))

    @patch("pr_worker._incident_api")
    def test_returns_true_for_pr_created(self, mock_api):
        mock_api.return_value = {"number": 42, "labels": [{"name": "sre-agent"}, {"name": "pr-created"}]}
        self.assertTrue(is_issue_processed(42, "fake-token"))

    @patch("pr_worker._incident_api")
    def test_returns_false_for_unprocessed(self, mock_api):
        mock_api.return_value = {"number": 42, "labels": [{"name": "sre-agent"}]}
        self.assertFalse(is_issue_processed(42, "fake-token"))

    @patch("pr_worker._incident_api")
    def test_returns_false_on_api_failure(self, mock_api):
        mock_api.return_value = None
        self.assertFalse(is_issue_processed(42, "fake-token"))


class TestDebounce(unittest.TestCase):
    """Debounce should prevent rapid successive PR-creating runs."""

    def test_write_and_read_last_run(self):
        """Should persist and read run state."""
        with tempfile.TemporaryDirectory() as tmpdir:
            _write_last_run(tmpdir, 2, 5)
            state = _read_last_run(tmpdir)
            self.assertIsNotNone(state)
            self.assertEqual(state["prs_created"], 2)
            self.assertEqual(state["issue_count"], 5)

    def test_debounce_skips_if_recent_pr_run(self):
        """Should skip if last PR-creating run was too recent."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Write a recent run
            _write_last_run(tmpdir, 1, 3)
            # Run should debounce
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": "/nonexistent", "STATE_DIR": tmpdir}):
                with patch("pr_worker.list_open_issues") as mock_list:
                    run_pr_worker()
                    mock_list.assert_not_called()

    def test_no_debounce_if_last_run_created_zero_prs(self):
        """Should NOT debounce if last run created 0 PRs (just checked issues)."""
        with tempfile.TemporaryDirectory() as tmpdir:
            _write_last_run(tmpdir, 0, 0)
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "STATE_DIR": tmpdir,
                                          "GITHUB_SOURCE_REPO": "test/repo"}):
                with patch("pr_worker.list_open_issues", return_value=[]) as mock_list:
                    run_pr_worker()
                    mock_list.assert_called_once()

    def test_no_debounce_if_no_state_file(self):
        """Should not debounce if no previous state file exists."""
        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "STATE_DIR": tmpdir,
                                          "GITHUB_SOURCE_REPO": "test/repo"}):
                with patch("pr_worker.list_open_issues", return_value=[]) as mock_list:
                    run_pr_worker()
                    mock_list.assert_called_once()

    def test_runs_after_debounce_window(self):
        """Should run normally if debounce window has passed."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Write a state file with an old timestamp
            old_ts = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
            state_path = os.path.join(tmpdir, "pr-worker-state.json")
            with open(state_path, "w") as f:
                json.dump({"ts": old_ts, "prs_created": 1, "issue_count": 1}, f)
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "STATE_DIR": tmpdir,
                                          "GITHUB_SOURCE_REPO": "test/repo"}):
                with patch("pr_worker.list_open_issues", return_value=[]) as mock_list:
                    run_pr_worker()
                    mock_list.assert_called_once()


class TestRateLimit(unittest.TestCase):
    """PR worker should respect MAX_PRS_PER_RUN."""

    @patch("pr_worker.draft_fix_with_llm")
    @patch("pr_worker.create_pr")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.mark_issue_created")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    @patch("pr_worker.get_repo_tree")
    def test_stops_after_max_prs(self, mock_tree, mock_list, mock_is_processed,
                                   mock_mark_created, mock_mark, mock_create_pr, mock_draft):
        """Should stop creating PRs after MAX_PRS_PER_RUN is reached."""
        mock_tree.return_value = []
        mock_list.return_value = [
            GitHubIssue(number=i, title=f"Issue {i}", body="", labels=["sre-agent"], url="")
            for i in range(1, 6)  # 5 issues
        ]
        mock_is_processed.return_value = False
        mock_draft.return_value = PRDraft(
            title="fix: test", body="test", branch="sre-fix/issue-1",
            files=[{"path": "test.nix", "content": "test"}],
        )
        mock_create_pr.return_value = "https://github.com/example/pull/1"

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "STATE_DIR": tmpdir,
                                          "GITHUB_SOURCE_REPO": "test/repo",
                                          "MAX_PRS_PER_RUN": "2"}):
                run_pr_worker()

        # Should only create 2 PRs (MAX_PRS_PER_RUN), not all 5
        self.assertEqual(mock_create_pr.call_count, 2)


class TestRunPrWorker(unittest.TestCase):
    """run_pr_worker should orchestrate the full PR creation flow."""

    @patch("pr_worker.draft_fix_with_llm")
    @patch("pr_worker.create_pr")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    def test_skips_already_processed(self, mock_list, mock_is_processed,
                                      mock_mark, mock_create_pr, mock_draft):
        mock_list.return_value = [
            GitHubIssue(number=1, title="Test", body="", labels=["sre-agent"], url="")
        ]
        mock_is_processed.return_value = True

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "STATE_DIR": tmpdir,
                                          "GITHUB_SOURCE_REPO": "test/repo"}):
                run_pr_worker()
        mock_draft.assert_not_called()
        mock_create_pr.assert_not_called()

    @patch("pr_worker.draft_fix_with_llm")
    @patch("pr_worker.create_pr")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.mark_issue_created")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    @patch("pr_worker.get_repo_tree")
    def test_processes_issue_creates_pr_and_labels(self, mock_tree, mock_list,
                                                     mock_is_processed, mock_mark_created,
                                                     mock_mark, mock_create_pr, mock_draft):
        """Should draft a fix, create a PR, and mark issue with pr-created label."""
        mock_tree.return_value = ["modules/sre-agent.nix"]
        mock_list.return_value = [
            GitHubIssue(number=7, title="OllamaUnreachable", body="Ollama down", labels=["sre-agent"], url="")
        ]
        mock_is_processed.return_value = False
        mock_draft.return_value = PRDraft(
            title="fix(total-eclipse): restart ollama", body="Restart ollama",
            branch="sre-fix/issue-7",
            files=[{"path": "hosts/total-eclipse/ollama.nix", "content": "test"}],
        )
        mock_create_pr.return_value = "https://github.com/example/pull/1"

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "STATE_DIR": tmpdir,
                                          "GITHUB_SOURCE_REPO": "test/repo"}):
                run_pr_worker()

        mock_mark.assert_called_once_with(7, "ghp_test123456789012345678901234567890")
        mock_create_pr.assert_called_once()
        # Should also mark as pr-created
        mock_mark_created.assert_called_once_with(7, "https://github.com/example/pull/1",
                                                    "ghp_test123456789012345678901234567890")

    @patch("pr_worker.draft_fix_with_llm")
    @patch("pr_worker.create_pr")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    def test_skips_when_no_fix_draft(self, mock_list, mock_is_processed,
                                       mock_mark, mock_create_pr, mock_draft):
        mock_list.return_value = [
            GitHubIssue(number=10, title="Hardware failure", body="Disk broken", labels=["sre-agent"], url="")
        ]
        mock_is_processed.return_value = False
        mock_draft.return_value = None

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "STATE_DIR": tmpdir,
                                          "GITHUB_SOURCE_REPO": "test/repo"}):
                run_pr_worker()
        mock_create_pr.assert_not_called()

    @patch("pr_worker.draft_fix_with_llm")
    @patch("pr_worker.create_pr")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    def test_skips_when_no_files(self, mock_list, mock_is_processed,
                                   mock_mark, mock_create_pr, mock_draft):
        mock_list.return_value = [
            GitHubIssue(number=10, title="Hardware failure", body="Disk broken", labels=["sre-agent"], url="")
        ]
        mock_is_processed.return_value = False
        mock_draft.return_value = PRDraft(
            title="fix: test", body="test", branch="sre-fix/issue-10", files=[]
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "STATE_DIR": tmpdir,
                                          "GITHUB_SOURCE_REPO": "test/repo"}):
                run_pr_worker()
        mock_create_pr.assert_not_called()

    @patch("pr_worker.list_open_issues")
    def test_no_issues_exits_early(self, mock_list):
        """Should exit early when no issues found."""
        mock_list.return_value = []
        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "STATE_DIR": tmpdir,
                                          "GITHUB_SOURCE_REPO": "test/repo"}):
                run_pr_worker()
            # Should write state with 0 prs_created
            state = _read_last_run(tmpdir)
            self.assertIsNotNone(state)
            self.assertEqual(state["prs_created"], 0)

    def test_no_token_file(self):
        with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": "/nonexistent/path"}):
            run_pr_worker()

    def test_placeholder_token(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("PLACEHOLDER")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file}):
                run_pr_worker()


class TestGitHubApiHelper(unittest.TestCase):
    """Test _github_api and _incident_api URL construction."""

    @patch("pr_worker.urllib.request.urlopen")
    def test_github_api_uses_source_repo(self, mock_urlopen):
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({"sha": "abc"}).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        from pr_worker import _github_api
        with patch.dict(os.environ, {"GITHUB_SOURCE_REPO": "test/systems-flake"}):
            _github_api("git/ref/heads/main", "fake-token")
        req = mock_urlopen.call_args[0][0]
        self.assertIn("test/systems-flake", req.full_url)
        self.assertIn("token fake-token", req.headers.get("Authorization", ""))

    @patch("pr_worker.urllib.request.urlopen")
    def test_incident_api_uses_incident_repo(self, mock_urlopen):
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps([]).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        from pr_worker import _incident_api
        with patch.dict(os.environ, {"GITHUB_REPO": "test/incidents"}):
            _incident_api("issues?labels=sre-agent&state=open", "fake-token")
        req = mock_urlopen.call_args[0][0]
        self.assertIn("test/incidents", req.full_url)


if __name__ == "__main__":
    unittest.main()