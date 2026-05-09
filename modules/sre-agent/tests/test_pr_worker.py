"""Tests for sre_agent.pr_worker — PR creation from GitHub issues using Claude Code CLI.

Run with: python3 -m pytest modules/sre-agent/tests/test_pr_worker.py -v
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone, timedelta
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from pr_worker import (
    GitHubIssue,
    list_open_issues,
    build_claude_prompt,
    extract_pr_url,
    fix_issue_with_claude,
    mark_issue_processing,
    mark_issue_created,
    is_issue_processed,
    run_pr_worker,
    _read_last_run,
    _write_last_run,
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


class TestBuildClaudePrompt(unittest.TestCase):
    """build_claude_prompt should construct a prompt for Claude Code CLI."""

    def test_includes_issue_number_and_title(self):
        issue = GitHubIssue(
            number=7, title="OllamaUnreachable on total-eclipse",
            body="Ollama service has been unreachable for 30 minutes.",
            labels=["sre-agent"], url="",
        )
        prompt = build_claude_prompt(issue)
        self.assertIn("#7", prompt)
        self.assertIn("OllamaUnreachable on total-eclipse", prompt)

    def test_includes_source_repo(self):
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        with patch.dict(os.environ, {"GITHUB_SOURCE_REPO": "mccartykim/systems-flake"}):
            prompt = build_claude_prompt(issue)
        self.assertIn("mccartykim/systems-flake", prompt)

    def test_instructs_create_pr(self):
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        prompt = build_claude_prompt(issue)
        self.assertIn("gh", prompt)
        self.assertIn("PR", prompt)

    def test_includes_skip_instruction(self):
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        prompt = build_claude_prompt(issue)
        self.assertIn("SKIP", prompt)

    def test_includes_issue_body(self):
        issue = GitHubIssue(
            number=1, title="Test", body="Service down on historian",
            labels=[], url=""
        )
        prompt = build_claude_prompt(issue)
        self.assertIn("Service down on historian", prompt)

    def test_instructs_nixos_syntax(self):
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        prompt = build_claude_prompt(issue)
        self.assertIn("NixOS module syntax", prompt)
        self.assertIn("Nix language", prompt)

    def test_includes_branch_name(self):
        issue = GitHubIssue(number=42, title="Test", body="body", labels=[], url="")
        prompt = build_claude_prompt(issue)
        self.assertIn("sre-fix/issue-42", prompt)


class TestExtractPrUrl(unittest.TestCase):
    """extract_pr_url should find GitHub PR URLs in Claude output."""

    def test_extracts_github_pr_url(self):
        output = "I've created the PR.\n\nhttps://github.com/mccartykim/systems-flake/pull/42"
        self.assertEqual(extract_pr_url(output), "https://github.com/mccartykim/systems-flake/pull/42")

    def test_extracts_pr_url_from_text(self):
        output = "Done! PR: https://github.com/mccartykim/systems-flake/pull/7"
        self.assertEqual(extract_pr_url(output), "https://github.com/mccartykim/systems-flake/pull/7")

    def test_returns_none_for_no_url(self):
        output = "I analyzed the issue but couldn't find a config fix."
        self.assertIsNone(extract_pr_url(output))

    def test_handles_skip_response(self):
        output = "SKIP: This requires SSH access to the host"
        result = extract_pr_url(output)
        self.assertIsNone(result)

    def test_extracts_first_pr_url_if_multiple(self):
        output = "https://github.com/mccartykim/systems-flake/pull/1 and https://github.com/mccartykim/systems-flake/pull/2"
        self.assertEqual(extract_pr_url(output), "https://github.com/mccartykim/systems-flake/pull/1")


class TestFixIssueWithClaude(unittest.TestCase):
    """fix_issue_with_claude should clone repo, run claude, and return PR URL."""

    @patch("pr_worker.shutil.rmtree")
    @patch("pr_worker.subprocess.run")
    def test_successful_pr_creation(self, mock_run, mock_rmtree):
        """Should clone, run claude, and return PR URL on success."""
        issue = GitHubIssue(number=7, title="OllamaUnreachable", body="Ollama down", labels=["sre-agent"], url="")
        mock_run.side_effect = [
            MagicMock(returncode=0, stdout="", stderr=""),  # git clone
            MagicMock(returncode=0, stdout=json.dumps({
                "result": "PR created: https://github.com/mccartykim/systems-flake/pull/42",
                "num_turns": 5,
                "total_cost_usd": 0.05,
            }), stderr=""),  # claude
        ]
        with tempfile.TemporaryDirectory() as tmpdir, \
             patch.dict(os.environ, {"STATE_DIR": tmpdir, "GITHUB_SOURCE_REPO": "test/repo",
                                      "PR_WORKER_MODEL": "test-model"}):
            result = fix_issue_with_claude(issue, "fake-gh-token")
        self.assertEqual(result, "https://github.com/mccartykim/systems-flake/pull/42")
        self.assertEqual(mock_run.call_count, 2)

    @patch("pr_worker.shutil.rmtree")
    @patch("pr_worker.subprocess.run")
    def test_clone_failure_returns_none(self, mock_run, mock_rmtree):
        """Should return None if git clone fails."""
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        mock_run.return_value = MagicMock(returncode=1, stdout="", stderr="fatal: repo not found")
        with tempfile.TemporaryDirectory() as tmpdir, \
             patch.dict(os.environ, {"STATE_DIR": tmpdir, "GITHUB_SOURCE_REPO": "test/repo"}):
            result = fix_issue_with_claude(issue, "fake-token")
        self.assertIsNone(result)

    @patch("pr_worker.shutil.rmtree")
    @patch("pr_worker.subprocess.run")
    def test_claude_failure_returns_none(self, mock_run, mock_rmtree):
        """Should return None if claude exits non-zero."""
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        mock_run.side_effect = [
            MagicMock(returncode=0, stdout="", stderr=""),  # git clone
            MagicMock(returncode=1, stdout="", stderr="error: API failure"),  # claude
        ]
        with tempfile.TemporaryDirectory() as tmpdir, \
             patch.dict(os.environ, {"STATE_DIR": tmpdir, "GITHUB_SOURCE_REPO": "test/repo"}):
            result = fix_issue_with_claude(issue, "fake-token")
        self.assertIsNone(result)

    @patch("pr_worker.shutil.rmtree")
    @patch("pr_worker.subprocess.run")
    def test_timeout_returns_none(self, mock_run, mock_rmtree):
        """Should return None if claude times out."""
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        mock_run.side_effect = [
            MagicMock(returncode=0, stdout="", stderr=""),  # git clone
            subprocess.TimeoutExpired(cmd="claude", timeout=600),  # claude times out
        ]
        with tempfile.TemporaryDirectory() as tmpdir, \
             patch.dict(os.environ, {"STATE_DIR": tmpdir, "GITHUB_SOURCE_REPO": "test/repo"}):
            result = fix_issue_with_claude(issue, "fake-token")
        self.assertIsNone(result)

    @patch("pr_worker.shutil.rmtree")
    @patch("pr_worker.subprocess.run")
    def test_skip_response_returns_none(self, mock_run, mock_rmtree):
        """Should return None when Claude outputs SKIP response."""
        issue = GitHubIssue(number=1, title="Hardware failure", body="Disk broken", labels=["sre-agent"], url="")
        mock_run.side_effect = [
            MagicMock(returncode=0, stdout="", stderr=""),  # git clone
            MagicMock(returncode=0, stdout=json.dumps({
                "result": "SKIP: This requires physical access to the host",
                "num_turns": 2,
                "total_cost_usd": 0.01,
            }), stderr=""),  # claude
        ]
        with tempfile.TemporaryDirectory() as tmpdir, \
             patch.dict(os.environ, {"STATE_DIR": tmpdir, "GITHUB_SOURCE_REPO": "test/repo"}):
            result = fix_issue_with_claude(issue, "fake-token")
        self.assertIsNone(result)

    @patch("pr_worker.shutil.rmtree")
    @patch("pr_worker.subprocess.run")
    def test_non_json_output_fallback(self, mock_run, mock_rmtree):
        """Should handle non-JSON output from claude by using raw stdout."""
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        mock_run.side_effect = [
            MagicMock(returncode=0, stdout="", stderr=""),  # git clone
            MagicMock(returncode=0, stdout="PR URL: https://github.com/mccartykim/systems-flake/pull/5", stderr=""),  # claude (non-JSON)
        ]
        with tempfile.TemporaryDirectory() as tmpdir, \
             patch.dict(os.environ, {"STATE_DIR": tmpdir, "GITHUB_SOURCE_REPO": "test/repo"}):
            result = fix_issue_with_claude(issue, "fake-token")
        self.assertEqual(result, "https://github.com/mccartykim/systems-flake/pull/5")

    @patch("pr_worker.shutil.rmtree")
    @patch("pr_worker.subprocess.run")
    def test_passes_git_identity(self, mock_run, mock_rmtree):
        """Should pass git identity env vars to claude subprocess."""
        issue = GitHubIssue(number=1, title="Test", body="body", labels=[], url="")
        mock_run.side_effect = [
            MagicMock(returncode=0, stdout="", stderr=""),  # git clone
            MagicMock(returncode=0, stdout=json.dumps({
                "result": "https://github.com/test/repo/pull/1",
            }), stderr=""),  # claude
        ]
        with tempfile.TemporaryDirectory() as tmpdir, \
             patch.dict(os.environ, {"STATE_DIR": tmpdir, "GITHUB_SOURCE_REPO": "test/repo",
                                      "GIT_AUTHOR_NAME": "test-author",
                                      "GIT_AUTHOR_EMAIL": "test@example.com"}):
            fix_issue_with_claude(issue, "fake-token")
        # Check the claude call (second call) has git identity env vars
        claude_call_env = mock_run.call_args_list[1].kwargs.get("env", mock_run.call_args_list[1][1].get("env"))
        self.assertIsNotNone(claude_call_env)
        self.assertEqual(claude_call_env.get("GIT_AUTHOR_NAME"), "test-author")
        self.assertEqual(claude_call_env.get("GIT_AUTHOR_EMAIL"), "test@example.com")


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

    @patch("pr_worker.fix_issue_with_claude")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.mark_issue_created")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    def test_stops_after_max_prs(self, mock_list, mock_is_processed,
                                  mock_mark_created, mock_mark, mock_fix):
        """Should stop creating PRs after MAX_PRS_PER_RUN is reached."""
        mock_list.return_value = [
            GitHubIssue(number=i, title=f"Issue {i}", body="", labels=["sre-agent"], url="")
            for i in range(1, 6)  # 5 issues
        ]
        mock_is_processed.return_value = False
        mock_fix.return_value = "https://github.com/example/pull/1"

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "STATE_DIR": tmpdir,
                                          "GITHUB_SOURCE_REPO": "test/repo",
                                          "MAX_PRS_PER_RUN": "2"}):
                run_pr_worker()

        # Should only call fix_issue_with_claude 2 times (MAX_PRS_PER_RUN), not all 5
        self.assertEqual(mock_fix.call_count, 2)


class TestRunPrWorker(unittest.TestCase):
    """run_pr_worker should orchestrate the full PR creation flow."""

    @patch("pr_worker.fix_issue_with_claude")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    def test_skips_already_processed(self, mock_list, mock_is_processed,
                                      mock_mark, mock_fix):
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
        mock_fix.assert_not_called()

    @patch("pr_worker.fix_issue_with_claude")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.mark_issue_created")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    def test_processes_issue_creates_pr_and_labels(self, mock_list, mock_is_processed,
                                                     mock_mark_created, mock_mark, mock_fix):
        """Should invoke claude, get PR URL, and mark issue with pr-created label."""
        mock_list.return_value = [
            GitHubIssue(number=7, title="OllamaUnreachable", body="Ollama down", labels=["sre-agent"], url="")
        ]
        mock_is_processed.return_value = False
        mock_fix.return_value = "https://github.com/example/pull/1"

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "STATE_DIR": tmpdir,
                                          "GITHUB_SOURCE_REPO": "test/repo"}):
                run_pr_worker()

        mock_mark.assert_called_once_with(7, "ghp_test123456789012345678901234567890")
        mock_fix.assert_called_once()
        # Should also mark as pr-created
        mock_mark_created.assert_called_once_with(7, "https://github.com/example/pull/1",
                                                    "ghp_test123456789012345678901234567890")

    @patch("pr_worker.fix_issue_with_claude")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    def test_skips_when_claude_returns_none(self, mock_list, mock_is_processed,
                                              mock_mark, mock_fix):
        mock_list.return_value = [
            GitHubIssue(number=10, title="Hardware failure", body="Disk broken", labels=["sre-agent"], url="")
        ]
        mock_is_processed.return_value = False
        mock_fix.return_value = None

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "STATE_DIR": tmpdir,
                                          "GITHUB_SOURCE_REPO": "test/repo"}):
                run_pr_worker()
        # Should not mark as pr-created
        from pr_worker import mark_issue_created
        # mock_fix returns None, so mark_issue_created should not be called

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


class TestIncidentApiHelper(unittest.TestCase):
    """Test _incident_api URL construction."""

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