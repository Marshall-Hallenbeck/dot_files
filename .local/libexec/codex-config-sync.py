#!/usr/bin/env python3
"""Reconcile Claude Code configuration into Codex without touching Codex-only entries."""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
import pathlib
import shutil
import time
from collections.abc import Iterator
from typing import Any

import tomlkit

if os.name == "nt":
    import msvcrt
else:
    import fcntl

HOME = pathlib.Path.home()
STATE_DIR = HOME / ".cache/codex-config-sync"


def load_json(path: pathlib.Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise TypeError(f"expected object in {path}")
    return value


@contextlib.contextmanager
def file_lock(path: pathlib.Path) -> Iterator[None]:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as handle:
        if os.name == "nt":
            if handle.tell() == 0:
                handle.write(b"0")
                handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
            try:
                yield
            finally:
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            fcntl.flock(handle, fcntl.LOCK_EX)
            yield


def replace_path_with_link_or_copy(source: pathlib.Path, target: pathlib.Path) -> bool:
    """Link on POSIX. Copy on Windows, where symlinks often require elevation."""
    if os.name == "nt":
        if target.is_dir():
            if _directory_digest(target) == _directory_digest(source):
                return False
            shutil.rmtree(target)
        elif target.exists() or target.is_symlink():
            target.unlink()
        if source.is_dir():
            shutil.copytree(source, target)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        return True
    if target.is_symlink() and target.resolve() == source.resolve():
        return False
    if target.is_dir() and not target.is_symlink():
        shutil.rmtree(target)
    elif target.exists() or target.is_symlink():
        target.unlink()
    target.symlink_to(source, target_is_directory=source.is_dir())
    return True


def _directory_digest(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    if not path.is_dir():
        return ""
    for child in sorted(item for item in path.rglob("*") if item.is_file()):
        digest.update(str(child.relative_to(path)).encode())
        digest.update(child.read_bytes())
    return digest.hexdigest()


def sync_skills(previous_managed: set[str]) -> tuple[list[str], list[str]]:
    source_root = HOME / ".claude/skills"
    target_root = HOME / ".agents/skills"
    target_root.mkdir(parents=True, exist_ok=True)
    # A community skill is installed under ~/.agents/skills and linked into
    # ~/.claude/skills so Claude can load it. Mirroring such a skill back would
    # replace the real directory with a link to itself, which deletes the
    # content and leaves an unresolvable loop. Leave those where they are, and
    # keep them out of the removal pass too: a self-referential skill dropping
    # out of the mirrored set must never delete the installed copy.
    resolved_target = target_root.resolve()
    current: set[str] = set()
    self_referential: set[str] = set()
    if source_root.is_dir():
        for path in source_root.iterdir():
            if path.name.startswith(".") or not path.is_dir():
                continue
            if resolved_target in path.resolve().parents:
                self_referential.add(path.name)
            else:
                current.add(path.name)
    changed: list[str] = []
    for name in sorted(previous_managed - current - self_referential):
        target = target_root / name
        if target.is_symlink() or target.exists():
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target)
            else:
                target.unlink()
            changed.append(f"removed:{name}")
    for name in sorted(current):
        source = source_root / name
        target = target_root / name
        if replace_path_with_link_or_copy(source, target):
            changed.append(f"{'copied' if os.name == 'nt' else 'linked'}:{name}")
    return sorted(current), changed


def disabled_synced_skills() -> set[str]:
    overrides = load_json(HOME / ".claude/settings.json").get("skillOverrides", {})
    return {
        name.removeprefix("anthropic-skills:")
        for name, value in overrides.items()
        if name.startswith("anthropic-skills:")
        and value == "off"
        and pathlib.Path(name.removeprefix("anthropic-skills:")).name
        == name.removeprefix("anthropic-skills:")
        and name.removeprefix("anthropic-skills:") not in {".", "..", ""}
    }


def prune_synced_skills() -> list[str]:
    excluded = disabled_synced_skills()
    changed: list[str] = []
    root = HOME / ".claude/skills/synced"
    for account in sorted(root.glob("*")):
        if not account.is_dir() or account.is_symlink():
            continue
        manifest_path = account / "manifest.json"
        manifest = load_json(manifest_path)
        skills = manifest.get("skills", [])
        retained = [skill for skill in skills if skill["skillId"] not in excluded]
        for name in sorted(excluded):
            target = account / name
            if target.is_symlink():
                target.unlink()
            elif target.is_dir():
                shutil.rmtree(target)
            else:
                continue
            changed.append(f"removed:synced/{account.name}/{name}")
        if retained != skills:
            manifest["skills"] = retained
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
            changed.append(f"filtered:synced/{account.name}/manifest.json")
    return changed


def prune_owned_links() -> list[str]:
    changed: list[str] = []
    owners = [
        (HOME / f".claude/{kind}", HOME / f".dot_files/.claude/{kind}")
        for kind in ("hooks", "agents", "commands")
    ]
    owners.append((HOME / ".codex/hooks", HOME / ".claude/hooks"))
    for directory, source in owners:
        for link in sorted(directory.glob("*")):
            if not link.is_symlink() or link.exists():
                continue
            target = pathlib.Path(os.path.abspath(link.parent / link.readlink()))
            if target == source / link.name:
                link.unlink()
                changed.append(f"removed:{link.relative_to(HOME)}")
    return changed


def desired_skill_exclusions() -> set[str]:
    paths: set[str] = set()
    for account in (HOME / ".claude/skills/synced").glob("*"):
        if not account.is_dir() or account.is_symlink():
            continue
        names = disabled_synced_skills()
        if (HOME / ".codex/skills/.system/skill-creator/SKILL.md").is_file():
            names.add("skill-creator")
        paths.update(str((account / name / "SKILL.md").resolve()) for name in names)
    for name in ("brainstorming", "systematic-debugging"):
        if (HOME / f".claude/skills/{name}/SKILL.md").is_file():
            paths.update(
                str(path.resolve()) for path in (HOME / ".codex/plugins/cache").glob(
                    f"*/superpowers/*/skills/{name}/SKILL.md"
                )
            )
    return paths


def sync_skill_exclusions(previous: set[str]) -> tuple[list[str], list[str]]:
    path = HOME / ".codex/config.toml"
    doc = tomlkit.parse(path.read_text()) if path.is_file() else tomlkit.document()
    desired = desired_skill_exclusions()
    skills = doc.setdefault("skills", tomlkit.table())
    entries = skills.setdefault("config", tomlkit.aot())
    changed: list[str] = []
    for index in range(len(entries) - 1, -1, -1):
        entry_path = str(entries[index].get("path", ""))
        if entry_path in previous - desired:
            del entries[index]
            changed.append(f"removed:{entry_path}")
    for excluded in sorted(desired):
        existing = next((entry for entry in entries if entry.get("path") == excluded), None)
        if existing is None:
            entry = tomlkit.table()
            entry["path"] = excluded
            entry["enabled"] = False
            entries.append(entry)
            changed.append(f"disabled:{excluded}")
        elif existing.get("enabled") is not False:
            existing["enabled"] = False
            changed.append(f"disabled:{excluded}")
    if changed:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(tomlkit.dumps(doc))
    return sorted(desired), changed


def sync_plugins() -> list[str]:
    settings = load_json(HOME / ".claude/settings.json").get("enabledPlugins", {}) or {}
    path = HOME / ".codex/config.toml"
    if not path.is_file():
        return []
    doc = tomlkit.parse(path.read_text())
    plugins = doc.get("plugins")
    if plugins is None:
        return []
    # These Claude hook plugins are either incompatible with Codex or stale
    # output styles that must not survive after Claude stops enabling them.
    compatibility_disabled = {
        "security-guidance@claude-plugins-official",
        "explanatory-output-style@claude-plugins-official",
        "learning-output-style@claude-plugins-official",
    }
    changed = []
    managed_names = set(settings) | compatibility_disabled
    for name in sorted(managed_names):
        if name not in plugins:
            continue
        desired = bool(settings.get(name, False)) and name not in compatibility_disabled
        if bool(plugins[name].get("enabled", True)) != desired:
            plugins[name]["enabled"] = desired
            changed.append(f"{name}:{str(desired).lower()}")
    rendered = tomlkit.dumps(doc)
    if path.read_text() != rendered:
        path.write_text(rendered)
    return changed


def sync_global_settings(path: pathlib.Path) -> list[str]:
    """Apply global Codex settings managed by this dotfiles repository."""
    path.parent.mkdir(parents=True, exist_ok=True)
    doc = tomlkit.parse(path.read_text()) if path.is_file() else tomlkit.document()
    changed: list[str] = []
    features = doc.get("features")
    if features is None:
        features = tomlkit.table()
        doc["features"] = features
    if features.get("default_mode_request_user_input") is not True:
        features["default_mode_request_user_input"] = True
        changed.append("default_mode_request_user_input:true")

    sandbox = doc.get("sandbox_workspace_write")
    if sandbox is None:
        sandbox = tomlkit.table()
        doc["sandbox_workspace_write"] = sandbox
    writable_roots = sandbox.get("writable_roots")
    if writable_roots is None:
        writable_roots = tomlkit.array()
        sandbox["writable_roots"] = writable_roots
    elif not isinstance(writable_roots, tomlkit.items.Array) or any(
        not isinstance(root, str) for root in writable_roots
    ):
        raise RuntimeError(
            "sandbox_workspace_write.writable_roots must be an array of strings"
        )
    if "/tmp" not in writable_roots:
        writable_roots.append("/tmp")
        changed.append("writable_root:/tmp")

    tui = doc.get("tui")
    if tui is None:
        tui = tomlkit.table()
        doc["tui"] = tui
    notification_events = ["agent-turn-complete", "approval-requested"]
    notifications = tui.get("notifications")
    if (
        not isinstance(notifications, tomlkit.items.Array)
        or list(notifications) != notification_events
    ):
        tui["notifications"] = tomlkit.array().multiline(False)
        tui["notifications"].extend(notification_events)
        changed.append("tui_notifications:agent-turn-complete,approval-requested")
    if tui.get("notification_method") != "bel":
        tui["notification_method"] = "bel"
        changed.append("tui_notification_method:bel")
    if tui.get("notification_condition") != "always":
        tui["notification_condition"] = "always"
        changed.append("tui_notification_condition:always")

    if changed:
        path.write_text(tomlkit.dumps(doc))
    return changed


def sync_hook_scripts() -> list[str]:
    target_root = HOME / ".codex/hooks"
    target_root.mkdir(parents=True, exist_ok=True)
    changed: list[str] = []
    for name in ("reinject-on-compact.sh",):
        source = HOME / ".claude/hooks" / name
        target = target_root / name
        if not source.is_file():
            raise RuntimeError(f"missing Claude hook source: {source}")
        if replace_path_with_link_or_copy(source, target):
            changed.append(f"{'copied' if os.name == 'nt' else 'linked'}:{name}")
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    state_file = STATE_DIR / "compat.json"
    with file_lock(STATE_DIR / "compat.lock"):
        state = load_json(state_file)
        link_changes = prune_owned_links()
        synced_changes = prune_synced_skills()
        hook_changes = sync_hook_scripts()
        skills, skill_changes = sync_skills(set(state.get("skillNames", [])))
        feature_changes = sync_global_settings(HOME / ".codex/config.toml")
        plugin_changes = sync_plugins()
        exclusions, exclusion_changes = sync_skill_exclusions(
            set(state.get("excludedSkillPaths", []))
        )
        result = {
            "status": "ok",
            "skills": skill_changes,
            "features": feature_changes,
            "plugins": plugin_changes,
            "hooks": hook_changes,
            "links": link_changes,
            "syncedSkills": synced_changes,
            "skillExclusions": exclusion_changes,
        }
        state.update({
            "skillNames": skills,
            "excludedSkillPaths": exclusions,
            "updatedAt": int(time.time()),
            "lastCompatResult": result,
        })
        state_file.write_text(json.dumps(state, indent=2) + "\n")
        if not args.quiet:
            print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
