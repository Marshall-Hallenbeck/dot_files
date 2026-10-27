import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import tomlkit

REPO = Path(__file__).resolve().parents[1]


def load_module(name: str):
    path = REPO / f".local/libexec/{name}.py"
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), path)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AiConfigCleanupTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.sync = load_module("codex-config-sync")
        self.audit = load_module("ai-config-audit")
        patcher = mock.patch.object(self.sync, "HOME", self.home)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.settings = self.home / ".claude/settings.json"
        self.settings.parent.mkdir()
        self.settings.write_text(json.dumps({"skillOverrides": {
            f"anthropic-skills:{name}": "off"
            for name in ("import-memory", "learn", "morning")
        }}))
        self.config = self.home / ".codex/config.toml"
        self.config.parent.mkdir()
        self.config.write_text("")

    def make_skill(self, relative: str) -> Path:
        path = self.home / relative / "SKILL.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("---\nname: example\ndescription: Example skill.\n---\n")
        return path

    def download_account(self) -> Path:
        account = self.home / ".claude/skills/synced/account"
        for name in ("import-memory", "learn", "morning", "pdf", "skill-creator"):
            self.make_skill(f".claude/skills/synced/account/{name}")
        (account / "manifest.json").write_text(json.dumps({
            "lastUpdated": 42,
            "skills": [{"skillId": name} for name in (
                "import-memory", "learn", "morning", "pdf", "skill-creator"
            )],
        }))
        return account

    def test_removed_skills_stay_excluded_after_another_download(self) -> None:
        account = self.download_account()
        for unused in range(2):
            changed = self.sync.prune_synced_skills()
            self.assertEqual(len(changed), 4)
            manifest = json.loads((account / "manifest.json").read_text())
            self.assertEqual(manifest["lastUpdated"], 42)
            self.assertEqual([skill["skillId"] for skill in manifest["skills"]],
                             ["pdf", "skill-creator"])
            self.assertFalse((account / "learn").exists())
            self.assertTrue((account / "pdf/SKILL.md").is_file())
            self.assertEqual(self.sync.prune_synced_skills(), [])
            paths = self.sync.sync_skill_exclusions(set())[0]
            self.assertIn(str(account / "learn/SKILL.md"), paths)
            self.assertEqual(self.audit.claude_codex_findings(self.home), [])
            self.download_account()

    def test_prune_never_follows_a_skill_symlink_outside_the_account(self) -> None:
        account = self.download_account()
        outside = self.make_skill("outside")
        (account / "learn/SKILL.md").unlink()
        (account / "learn").rmdir()
        (account / "learn").symlink_to(outside.parent, target_is_directory=True)
        self.sync.prune_synced_skills()
        self.assertTrue(outside.is_file())
        self.assertFalse((account / "learn").is_symlink())

    def test_invalid_exclusion_cannot_delete_another_path(self) -> None:
        self.settings.write_text(json.dumps({"skillOverrides": {
            "anthropic-skills:../outside": "off",
            "anthropic-skills:..": "off",
            "anthropic-skills:.": "off",
        }}))
        self.download_account()
        outside = self.make_skill(".claude/skills/synced/outside")
        self.assertEqual(self.sync.disabled_synced_skills(), set())
        self.sync.prune_synced_skills()
        self.assertTrue(outside.is_file())

    def test_prune_removes_only_owned_dead_links(self) -> None:
        for kind in ("hooks", "agents", "commands"):
            directory = self.home / f".claude/{kind}"
            directory.mkdir()
            (directory / "old").symlink_to(self.home / f".dot_files/.claude/{kind}/old")
            (directory / "host-local").symlink_to(self.home / "not-managed")
            (directory / "real-file").write_text("keep")
        codex = self.home / ".codex/hooks"
        codex.mkdir()
        (codex / "old").symlink_to(self.home / ".claude/hooks/old")
        self.assertEqual(len(self.sync.prune_owned_links()), 4)
        for kind in ("hooks", "agents", "commands"):
            directory = self.home / f".claude/{kind}"
            self.assertFalse((directory / "old").is_symlink())
            self.assertTrue((directory / "host-local").is_symlink())
            self.assertEqual((directory / "real-file").read_text(), "keep")
        self.assertEqual(self.sync.prune_owned_links(), [])

    def test_exclusions_follow_plugin_updates_and_preserve_user_entries(self) -> None:
        self.make_skill(".claude/skills/brainstorming")
        old = self.make_skill(".codex/plugins/cache/vendor/superpowers/1/skills/brainstorming")
        self.config.write_text('[[skills.config]]\npath = "/custom/SKILL.md"\nenabled = false\n')
        previous = self.sync.sync_skill_exclusions(set())[0]
        self.assertIn(str(old), previous)
        self.assertEqual(self.sync.sync_skill_exclusions(set(previous))[1], [])
        old.unlink()
        new = self.make_skill(".codex/plugins/cache/vendor/superpowers/2/skills/brainstorming")
        current, changed = self.sync.sync_skill_exclusions(set(previous))
        self.assertEqual(current, [str(new)])
        self.assertEqual(len(changed), 2)
        doc = tomlkit.parse(self.config.read_text()).unwrap()
        self.assertEqual({entry["path"] for entry in doc["skills"]["config"]},
                         {"/custom/SKILL.md", str(new)})

    def test_plugin_skill_remains_available_without_local_replacement(self) -> None:
        self.make_skill(".codex/plugins/cache/vendor/superpowers/1/skills/brainstorming")
        self.assertEqual(self.sync.desired_skill_exclusions(), set())

    def test_hidden_skill_trash_is_not_mirrored(self) -> None:
        self.make_skill(".claude/skills/.trash/old")
        self.make_skill(".claude/skills/commit")
        names = self.sync.sync_skills(set())[0]
        self.assertEqual(names, ["commit"])
        self.assertFalse((self.home / ".agents/skills/.trash").exists())

    def test_audit_detects_returned_skills_and_missing_exclusions(self) -> None:
        self.download_account()
        self.make_skill(".codex/skills/.system/skill-creator")
        findings = self.audit.claude_codex_findings(self.home)
        self.assertEqual(sum("returned" in finding for finding in findings), 3)
        self.assertEqual(sum("missing Codex" in finding for finding in findings), 4)
        self.sync.prune_synced_skills()
        self.sync.sync_skill_exclusions(set())
        self.assertEqual(self.audit.claude_codex_findings(self.home), [])

    def test_audit_reports_dead_links_plugin_scopes_and_stale_references(self) -> None:
        path = self.make_skill(".claude/skills/example")
        path.write_text("Read [guide](references/missing.md).\n")
        (path.parent / "references").mkdir()
        (self.home / ".claude/agents").mkdir()
        (self.home / ".claude/agents/dead.md").symlink_to(self.home / "missing")
        registry = self.home / ".claude/plugins/installed_plugins.json"
        registry.parent.mkdir()
        registry.write_text(json.dumps({"plugins": {"example@vendor": [
            {"scope": "user"}, {"scope": "project", "projectPath": str(REPO)},
        ]}}))
        findings = self.audit.claude_codex_findings(self.home)
        self.assertEqual(len(findings), 3)
        self.assertTrue(any("broken AI config link" in finding for finding in findings))
        self.assertTrue(any("duplicate user/project" in finding for finding in findings))
        self.assertTrue(any("broken skill reference" in finding for finding in findings))

    def test_audit_reports_stale_version_paths_and_new_unexcluded_version(self) -> None:
        self.make_skill(".claude/skills/brainstorming")
        self.make_skill(".codex/plugins/cache/vendor/superpowers/2/skills/brainstorming")
        self.config.write_text('[[skills.config]]\n'
                              f'path = "{self.home}/.codex/plugins/cache/old/SKILL.md"\n'
                              'enabled = false\n')
        findings = self.audit.claude_codex_findings(self.home)
        self.assertEqual(len(findings), 2)
        self.assertTrue(any("stale Codex" in finding for finding in findings))
        self.assertTrue(any("missing Codex" in finding for finding in findings))

    def test_audit_reports_missing_required_config(self) -> None:
        self.config.unlink()
        findings = self.audit.claude_codex_findings(self.home)
        self.assertEqual(len(findings), 1)
        self.assertIn(str(self.config), findings[0])


if __name__ == "__main__":
    unittest.main()
