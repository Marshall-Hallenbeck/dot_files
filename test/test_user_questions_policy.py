"""Keep shared question behavior and Claude's idle settings explicit."""
import json
from pathlib import Path
import subprocess
import tempfile
import os
import unittest

REPO = Path(__file__).resolve().parents[1]


class UserQuestionsPolicyTests(unittest.TestCase):
    def test_shared_policy_requires_each_native_question_tool(self):
        text = (REPO / "global-AGENTS.md").read_text()
        self.assertIn("## User Questions (Claude and Codex)", text)
        self.assertIn("Claude must use `AskUserQuestion`", text)
        self.assertIn("Codex must use `request_user_input`", text)
        self.assertIn("Do not ask answer-required questions in ordinary chat text", text)
        self.assertIn("Wait for the user's explicit answer or cancellation", text)
        self.assertIn("autoResolutionMs", text)
        self.assertIn("do not perform work that depends on it", text)

    def test_dotfiles_changes_have_standing_publish_authority(self):
        text = (REPO / "global-AGENTS.md").read_text()
        self.assertIn("For requested changes to `~/.dot_files`", text)
        self.assertIn("commit and push the in-scope changes", text)
        self.assertIn("Verify that the remote branch contains the commit", text)
        self.assertIn("For other repositories, do not commit", text)
        self.assertIn("Do not include unrelated user changes", text)

    def test_claude_disables_both_question_and_forwarded_dialog_expiry(self):
        settings = json.loads((REPO / ".claude/settings.json").read_text())
        self.assertEqual(settings.get("askUserQuestionTimeout"), "never")
        self.assertEqual(settings.get("dialogExpiry"), "never")

    def test_compaction_reinjects_shared_question_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / ".claude").mkdir()
            (home / ".claude/CLAUDE.md").symlink_to(REPO / "global-AGENTS.md")
            result = subprocess.run(
                ["bash", str(REPO / ".claude/hooks/reinject-on-compact.sh")],
                input='{"source":"compact"}', text=True, capture_output=True,
                cwd=home, env=os.environ | {"HOME": str(home)}, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Claude must use `AskUserQuestion`", result.stdout)
            self.assertIn("Codex must use `request_user_input`", result.stdout)


if __name__ == "__main__":
    unittest.main()
