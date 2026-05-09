"""Tests for sre_agent.pr_worker — PR creation from GitHub issues.

Run with: python3 -m pytest modules/sre-agent/tests/test_pr_worker.py -v
"""
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from pr_worker import (
    GitHubIssue,
    PRDraft,
    list_open_issues,
    build_fix_prompt,
    draft_fix_with_llm,
    create_pr,
    mark_issue_processing,
    is_issue_processed,
    run_pr_worker,
)


class TestListOpenIssues(unittest.TestCase):
    """list_open_issues should fetch sre-agent labeled issues from GitHub."""

    @patch("pr_worker._incident_api")
    def test_returns_issues_with_label(self, mock_api):
        """Should return GitHubIssue objects for open issues."""
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
        """Should exclude pull requests from the issue list."""
        mock_api.return_value = [
            {
                "number": 1,
                "title": "A real issue",
                "body": "",
                "labels": [{"name": "sre-agent"}],
                "html_url": "https://github.com/example/issues/1",
            },
            {
                "number": 2,
                "title": "A pull request",
                "body": "",
                "labels": [{"name": "sre-agent"}],
                "html_url": "https://github.com/example/issues/2",
                "pull_request": {"url": "https://api.github.com/repos/example/issues/2"},
            },
        ]
        issues = list_open_issues("fake-token")
        self.assertEqual(len(issues), 1)
        self.assertEqual(issues[0].number, 1)

    @patch("pr_worker._incident_api")
    def test_handles_empty_response(self, mock_api):
        """Should return empty list when API returns None or empty."""
        mock_api.return_value = None
        issues = list_open_issues("fake-token")
        self.assertEqual(issues, [])

        mock_api.return_value = []
        issues = list_open_issues("fake-token")
        self.assertEqual(issues, [])

    @patch("pr_worker._incident_api")
    def test_handles_null_body(self, mock_api):
        """Should handle null body gracefully."""
        mock_api.return_value = [
            {
                "number": 5,
                "title": "Issue with null body",
                "body": None,
                "labels": [{"name": "sre-agent"}],
                "html_url": "https://github.com/example/issues/5",
            }
        ]
        issues = list_open_issues("fake-token")
        self.assertEqual(len(issues), 1)
        self.assertEqual(issues[0].body, "")


class TestBuildFixPrompt(unittest.TestCase):
    """build_fix_prompt should construct an LLM prompt for drafting NixOS fixes."""

    def test_includes_issue_number_and_title(self):
        issue = GitHubIssue(
            number=7,
            title="OllamaUnreachable on total-eclipse",
            body="Ollama service has been unreachable for 30 minutes.",
            labels=["sre-agent"],
            url="https://github.com/mccartykim/homelab-incidents/issues/7",
        )
        prompt = build_fix_prompt(issue)
        self.assertIn("#7", prompt)
        self.assertIn("OllamaUnreachable on total-eclipse", prompt)
        self.assertIn("Ollama service has been unreachable", prompt)

    def test_instructs_json_format(self):
        issue = GitHubIssue(
            number=1, title="Test", body="body", labels=[], url=""
        )
        prompt = build_fix_prompt(issue)
        self.assertIn('"title"', prompt)
        self.assertIn('"branch"', prompt)
        self.assertIn('"files"', prompt)

    def test_includes_skip_option(self):
        issue = GitHubIssue(
            number=1, title="Test", body="body", labels=[], url=""
        )
        prompt = build_fix_prompt(issue)
        self.assertIn('"skip"', prompt)
        self.assertIn("cannot be fixed with a config change", prompt)

    def test_branch_includes_issue_number(self):
        issue = GitHubIssue(
            number=42, title="Test", body="body", labels=[], url=""
        )
        prompt = build_fix_prompt(issue)
        self.assertIn("sre-fix/issue-42", prompt)


class TestDraftFixWithLLM(unittest.TestCase):
    """draft_fix_with_llm should call Ollama and parse the response."""

    @patch("pr_worker.urllib.request.urlopen")
    def test_local_ollama_json_response(self, mock_urlopen):
        """Should parse structured JSON from local Ollama."""
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

        issue = GitHubIssue(
            number=7, title="OllamaUnreachable", body="Ollama down", labels=["sre-agent"], url=""
        )
        with patch.dict(os.environ, {"OLLAMA_HOST": "http://localhost:11434", "PR_WORKER_MODEL": "qwen3:8b"}):
            draft = draft_fix_with_llm(issue)
        self.assertIsNotNone(draft)
        self.assertEqual(draft.title, "fix(total-eclipse): restart ollama service")
        self.assertEqual(draft.branch, "sre-fix/issue-7")
        self.assertEqual(len(draft.files), 1)

    @patch("pr_worker.urllib.request.urlopen")
    def test_skip_response(self, mock_urlopen):
        """Should return None when LLM says issue can't be fixed with config."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "message": {"content": json.dumps({
                "skip": True,
                "reason": "Requires SSH into host to restart service",
            })},
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        issue = GitHubIssue(
            number=10, title="Hardware failure", body="Disk is broken", labels=["sre-agent"], url=""
        )
        with patch.dict(os.environ, {"OLLAMA_HOST": "http://localhost:11434", "PR_WORKER_MODEL": "qwen3:8b"}):
            draft = draft_fix_with_llm(issue)
        self.assertIsNone(draft)

    @patch("pr_worker.urllib.request.urlopen")
    def test_local_failure_returns_none(self, mock_urlopen):
        """Should return None when local Ollama is unreachable."""
        mock_urlopen.side_effect = ConnectionError("ollama down")

        issue = GitHubIssue(
            number=1, title="Test", body="body", labels=[], url=""
        )
        with patch.dict(os.environ, {"OLLAMA_HOST": "http://localhost:11434"}):
            draft = draft_fix_with_llm(issue)
        self.assertIsNone(draft)

    @patch("pr_worker.urllib.request.urlopen")
    def test_local_invalid_json_falls_back(self, mock_urlopen):
        """Should handle invalid JSON from local Ollama gracefully."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "message": {"content": "not valid json at all"},
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        issue = GitHubIssue(
            number=1, title="Test", body="body", labels=[], url=""
        )
        with patch.dict(os.environ, {"OLLAMA_HOST": "http://localhost:11434", "PR_WORKER_MODEL": "qwen3:8b"}):
            draft = draft_fix_with_llm(issue)
        # Invalid JSON should not crash, returns None (no cloud fallback in this test)
        self.assertIsNone(draft)


class TestCreatePR(unittest.TestCase):
    """create_pr should use Git Data API to create a branch and PR."""

    @patch("pr_worker._github_api")
    def test_creates_branch_tree_commit_pr(self, mock_api):
        """Should create blob, tree, commit, branch ref, and PR in sequence."""
        draft = PRDraft(
            title="fix(maitred): restart ollama",
            body="Restart the ollama service on maitred",
            branch="sre-fix/issue-7",
            files=[{"path": "hosts/maitred/ollama.nix", "content": "{ config, ... }: { services.ollama.enable = true; }"}],
        )

        # Mock the sequence of API calls
        call_count = [0]
        api_responses = {
            # 1. Get main branch SHA
            "git/ref/heads/main": {"object": {"sha": "abc123main"}},
            # 2. Get commit tree SHA
            "git/commits/abc123main": {"tree": {"sha": "tree123"}},
            # 3. Create branch
            "git/refs": {"ref": "refs/heads/sre-fix/issue-7"},
            # 4. Create blob
            "git/blobs": {"sha": "blob456"},
            # 5. Create tree
            "git/trees": {"sha": "newtree789"},
            # 6. Create commit
            "git/commits": {"sha": "commitxyz"},
            # 7. Update branch ref (PATCH)
            "git/refs/heads/sre-fix/issue-7": {"ok": True},
            # 8. Create PR
            "pulls": {"html_url": "https://github.com/mccartykim/systems-flake/pull/99"},
        }

        def api_side_effect(path, token, method="GET", data=None):
            # Determine key based on path and method
            key = path
            if method == "POST" and path == "git/blobs":
                key = "git/blobs"
            elif method == "POST" and path == "git/trees":
                key = "git/trees"
            elif method == "POST" and path == "git/commits":
                key = "git/commits"
            elif method == "PATCH":
                key = path
            elif method == "POST" and path == "pulls":
                key = "pulls"
            return api_responses.get(key, {"ok": True})

        mock_api.side_effect = api_side_effect

        result = create_pr(draft, "fake-token")
        self.assertEqual(result, "https://github.com/mccartykim/systems-flake/pull/99")
        # Should have called _github_api at least 6 times
        self.assertGreaterEqual(mock_api.call_count, 6)

    @patch("pr_worker._github_api")
    def test_returns_none_when_main_ref_fails(self, mock_api):
        """Should return None if getting main branch ref fails."""
        mock_api.return_value = None
        draft = PRDraft(
            title="fix: test",
            body="test fix",
            branch="sre-fix/issue-1",
            files=[{"path": "test.nix", "content": "{}"}],
        )
        result = create_pr(draft, "fake-token")
        self.assertIsNone(result)

    @patch("pr_worker._github_api")
    def test_returns_none_when_branch_fails(self, mock_api):
        """Should return None if creating branch fails."""
        call_count = [0]

        def side_effect(path, token, method="GET", data=None):
            call_count[0] += 1
            if call_count[0] == 1:
                return {"object": {"sha": "abc123"}}  # main ref
            if call_count[0] == 2:
                return {"tree": {"sha": "tree123"}}  # commit
            return None  # branch creation fails

        mock_api.side_effect = side_effect
        draft = PRDraft(
            title="fix: test", body="test", branch="sre-fix/issue-1",
            files=[{"path": "test.nix", "content": "{}"}],
        )
        result = create_pr(draft, "fake-token")
        self.assertIsNone(result)

    @patch("pr_worker._github_api")
    def test_returns_none_when_no_files(self, mock_api):
        """Should return None if no files to commit."""
        # If all blob creations fail, tree_items is empty
        call_count = [0]

        def side_effect(path, token, method="GET", data=None):
            call_count[0] += 1
            if call_count[0] == 1:
                return {"object": {"sha": "abc123"}}
            if call_count[0] == 2:
                return {"tree": {"sha": "tree123"}}
            if call_count[0] == 3:
                return {"ref": "refs/heads/sre-fix/issue-1"}  # branch
            if call_count[0] == 4:
                return None  # blob fails
            return {"sha": "mocksha"}

        mock_api.side_effect = side_effect
        draft = PRDraft(
            title="fix: test", body="test", branch="sre-fix/issue-1",
            files=[{"path": "test.nix", "content": "{}"}],
        )
        result = create_pr(draft, "fake-token")
        self.assertIsNone(result)

    @patch("pr_worker._github_api")
    def test_pr_body_references_issue(self, mock_api):
        """PR body should reference the issue number."""
        draft = PRDraft(
            title="fix(maitred): restart ollama",
            body="Restart the ollama service",
            branch="sre-fix/issue-7",
            files=[{"path": "hosts/maitred/ollama.nix", "content": "test"}],
        )

        pr_data = {}
        def capture_pr_call(path, token, method="GET", data=None):
            if path == "pulls" and method == "POST":
                pr_data.update(data)
                return {"html_url": "https://github.com/example/pull/1"}
            if path == "git/ref/heads/main":
                return {"object": {"sha": "abc"}}
            if path == "git/commits/abc":
                return {"tree": {"sha": "tree123"}}
            if path == "git/refs":
                return {"ref": "refs/heads/test"}
            if path == "git/blobs":
                return {"sha": "blob1"}
            if path == "git/trees":
                return {"sha": "newtree"}
            if path == "git/commits" and method == "POST":
                return {"sha": "commit1"}
            return {"sha": "default"}

        mock_api.side_effect = capture_pr_call
        create_pr(draft, "fake-token")

        # The PR body should contain the issue number reference
        self.assertIn("7", pr_data.get("body", ""))


class TestMarkIssueProcessing(unittest.TestCase):
    """mark_issue_processing should add pr-processing label to an issue."""

    @patch("pr_worker._incident_api")
    def test_adds_label(self, mock_api):
        """Should POST pr-processing label to the issue."""
        mark_issue_processing(42, "fake-token")
        mock_api.assert_called_once()
        call_args = mock_api.call_args
        self.assertEqual(call_args[0][0], "issues/42/labels")
        self.assertEqual(call_args[1]["method"], "POST")
        self.assertIn("pr-processing", call_args[1]["data"]["labels"])


class TestIsIssueProcessed(unittest.TestCase):
    """is_issue_processed should check if an issue already has pr-processing label."""

    @patch("pr_worker._incident_api")
    def test_returns_true_for_pr_processing(self, mock_api):
        """Should return True if issue has pr-processing label."""
        mock_api.return_value = {
            "number": 42,
            "labels": [{"name": "sre-agent"}, {"name": "pr-processing"}],
        }
        self.assertTrue(is_issue_processed(42, "fake-token"))

    @patch("pr_worker._incident_api")
    def test_returns_true_for_pr_created(self, mock_api):
        """Should return True if issue has pr-created label."""
        mock_api.return_value = {
            "number": 42,
            "labels": [{"name": "sre-agent"}, {"name": "pr-created"}],
        }
        self.assertTrue(is_issue_processed(42, "fake-token"))

    @patch("pr_worker._incident_api")
    def test_returns_false_for_unprocessed(self, mock_api):
        """Should return False if issue only has sre-agent label."""
        mock_api.return_value = {
            "number": 42,
            "labels": [{"name": "sre-agent"}],
        }
        self.assertFalse(is_issue_processed(42, "fake-token"))

    @patch("pr_worker._incident_api")
    def test_returns_false_on_api_failure(self, mock_api):
        """Should return False if GitHub API fails."""
        mock_api.return_value = None
        self.assertFalse(is_issue_processed(42, "fake-token"))


class TestRunPrWorker(unittest.TestCase):
    """run_pr_worker should orchestrate the full PR creation flow."""

    @patch("pr_worker.draft_fix_with_llm")
    @patch("pr_worker.create_pr")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    def test_skips_already_processed(self, mock_list, mock_is_processed,
                                      mock_mark, mock_create_pr, mock_draft):
        """Should skip issues that already have pr-processing label."""
        mock_list.return_value = [
            GitHubIssue(number=1, title="Test", body="", labels=["sre-agent"], url="")
        ]
        mock_is_processed.return_value = True

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "GITHUB_SOURCE_REPO": "test/repo"}):
                run_pr_worker()

        mock_draft.assert_not_called()
        mock_create_pr.assert_not_called()

    @patch("pr_worker.draft_fix_with_llm")
    @patch("pr_worker.create_pr")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    def test_processes_issue_creates_pr(self, mock_list, mock_is_processed,
                                          mock_mark, mock_create_pr, mock_draft):
        """Should draft a fix and create a PR for an unprocessed issue."""
        mock_list.return_value = [
            GitHubIssue(number=7, title="OllamaUnreachable", body="Ollama down", labels=["sre-agent"], url="")
        ]
        mock_is_processed.return_value = False
        mock_draft.return_value = PRDraft(
            title="fix(total-eclipse): restart ollama",
            body="Restart ollama",
            branch="sre-fix/issue-7",
            files=[{"path": "hosts/total-eclipse/ollama.nix", "content": "test"}],
        )
        mock_create_pr.return_value = "https://github.com/example/pull/1"

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "GITHUB_SOURCE_REPO": "test/repo"}):
                run_pr_worker()

        mock_mark.assert_called_once_with(7, "ghp_test123456789012345678901234567890")
        mock_create_pr.assert_called_once()

    @patch("pr_worker.draft_fix_with_llm")
    @patch("pr_worker.create_pr")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    def test_skips_when_no_fix_draft(self, mock_list, mock_is_processed,
                                       mock_mark, mock_create_pr, mock_draft):
        """Should not create a PR when LLM returns no fix draft."""
        mock_list.return_value = [
            GitHubIssue(number=10, title="Hardware failure", body="Disk broken", labels=["sre-agent"], url="")
        ]
        mock_is_processed.return_value = False
        mock_draft.return_value = None

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "GITHUB_SOURCE_REPO": "test/repo"}):
                run_pr_worker()

        mock_create_pr.assert_not_called()

    @patch("pr_worker.draft_fix_with_llm")
    @patch("pr_worker.create_pr")
    @patch("pr_worker.mark_issue_processing")
    @patch("pr_worker.is_issue_processed")
    @patch("pr_worker.list_open_issues")
    def test_skips_when_no_files(self, mock_list, mock_is_processed,
                                   mock_mark, mock_create_pr, mock_draft):
        """Should not create a PR when draft has no files."""
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
            with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": token_file, "GITHUB_SOURCE_REPO": "test/repo"}):
                run_pr_worker()

        mock_create_pr.assert_not_called()

    def test_no_token_file(self):
        """Should exit early if no GitHub token is configured."""
        with patch.dict(os.environ, {"GITHUB_TOKEN_FILE": "/nonexistent/path"}):
            # Should not raise, just return early
            run_pr_worker()

    def test_placeholder_token(self):
        """Should exit early if token is a placeholder."""
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
        """_github_api should use GITHUB_SOURCE_REPO env var."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({"sha": "abc"}).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        from pr_worker import _github_api
        with patch.dict(os.environ, {"GITHUB_SOURCE_REPO": "test/systems-flake"}):
            result = _github_api("git/ref/heads/main", "fake-token")
        req = mock_urlopen.call_args[0][0]
        self.assertIn("test/systems-flake", req.full_url)
        self.assertIn("token fake-token", req.headers.get("Authorization", ""))

    @patch("pr_worker.urllib.request.urlopen")
    def test_incident_api_uses_incident_repo(self, mock_urlopen):
        """_incident_api should use GITHUB_REPO env var."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps([]).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        from pr_worker import _incident_api
        with patch.dict(os.environ, {"GITHUB_REPO": "test/incidents"}):
            result = _incident_api("issues?labels=sre-agent&state=open", "fake-token")
        req = mock_urlopen.call_args[0][0]
        self.assertIn("test/incidents", req.full_url)


if __name__ == "__main__":
    unittest.main()