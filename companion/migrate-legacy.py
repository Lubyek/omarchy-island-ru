#!/usr/bin/env python3
"""Replace upstream Island without discarding local edits or user settings."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

OLD_IDS = {"guilhermerisu.island", "guilhermerisu.notifications"}
COMMAND = re.compile(r"(\bomarchy-shell\s+)guilhermerisu\.island(?=\s|['\"]|$)")
NOTIFICATIONS = re.compile(r"(\bomarchy-shell\s+)island-notifications(?=\s|['\"]|$)")
LOADER = re.compile(
    r"require\s*\(\s*(['\"])default\.hypr\.require_optional\1\s*\)"
    r"\.module\s*\(\s*(['\"])hypr\.island-bindings\2\s*\)"
    r"|require\s*\(\s*(['\"])hypr\.island-bindings\3\s*\)"
)


def retarget(text):
    text = COMMAND.sub(r"\1huesos.island", text)
    return NOTIFICATIONS.sub(r"\1huesos-island-notifications", text)


def atomic_write(path, data, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def migrate(home_dir, state_dir):
    config_dir = home_dir / ".config/omarchy"
    plugins_dir = config_dir / "plugins"
    hypr_dir = home_dir / ".config/hypr"
    writes = {}
    moves = []

    def plan_text(path, text, mode=0o600):
        data = text.encode("utf-8")
        if path.is_file() and path.read_bytes() == data:
            return
        if path.is_symlink():
            raise ValueError(f"Will not replace a symlinked configuration: {path}")
        writes[path] = (data, path.stat().st_mode & 0o777 if path.exists() else mode)

    # Parse before changing anything, so a malformed shell config stays intact.
    config = config_dir / "shell.json"
    if config.exists():
        original = json.loads(config.read_text())
        if not isinstance(original, dict):
            raise ValueError("shell.json must be a JSON object")
        updated = json.loads(json.dumps(original))
        for key in ("plugins", "disabledPlugins", "cloneSourceRestores"):
            if isinstance(updated.get(key), list):
                updated[key] = [entry for entry in updated[key]
                                if (entry.get("id") if isinstance(entry, dict) else entry) not in OLD_IDS]
        bar = updated.get("bar", {})
        if isinstance(bar, dict):
            if bar.get("id") == "guilhermerisu.island":
                bar["id"] = "huesos.island"
            layout = bar.get("layout", {})
            if not isinstance(layout, dict):
                raise ValueError("The bar layout must be a JSON object")
            for section, entries in layout.items():
                if isinstance(entries, list):
                    bar["layout"][section] = [entry for entry in entries
                                             if (entry.get("id") if isinstance(entry, dict) else entry) not in OLD_IDS]
        if updated != original:
            plan_text(config, json.dumps(updated, ensure_ascii=False, indent=2) + "\n")

    old_settings = config_dir / "island.json"
    new_settings = config_dir / "huesos-island.json"
    if old_settings.is_file() and not new_settings.exists():
        # Do not import an invalid settings file into the new plugin.
        settings = json.loads(old_settings.read_text())
        if not isinstance(settings, dict):
            raise ValueError("Previous Island settings must be a JSON object")
        plan_text(new_settings, json.dumps(settings, ensure_ascii=False, indent=4) + "\n")

    old_keys = hypr_dir / "island-bindings.lua"
    new_keys = hypr_dir / "huesos-island-bindings.lua"
    if old_keys.is_file() and not new_keys.exists():
        plan_text(new_keys, retarget(old_keys.read_text()))
    if old_keys.exists() or old_keys.is_symlink():
        moves.append(old_keys)

    # Retarget just the old Island IPC commands. Other menu overrides and
    # custom shortcuts retain their labels, keys and unrelated commands.
    menu = config_dir / "extensions/omarchy-menu.jsonc"
    if menu.is_file():
        before = menu.read_text()
        after = retarget(before)
        if after != before:
            plan_text(menu, after)
    for path in hypr_dir.glob("*.lua"):
        if path == old_keys:
            continue
        before = path.read_text()
        after = retarget(before)
        if path.name == "hyprland.lua":
            after = LOADER.sub("", after)
        if after != before:
            plan_text(path, after)

    for plugin_id in sorted(OLD_IDS):
        path = plugins_dir / plugin_id
        if path.exists() or path.is_symlink():
            if path.is_dir() and not path.is_symlink():
                manifest = path / "manifest.json"
                if not manifest.is_file() or json.loads(manifest.read_text()).get("id") != plugin_id:
                    raise ValueError(f"Unexpected plugin folder; leaving it intact: {path}")
            moves.append(path)

    if not writes and not moves:
        print("No previous Island installation to replace")
        return

    backup_root = state_dir / "omarchy/backups"
    backup_root.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = Path(tempfile.mkdtemp(prefix=f"replace-island-{stamp}-", dir=backup_root))
    originals = {}
    for path in writes:
        if path.exists():
            saved = backup / "config" / path.relative_to(home_dir)
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, saved)
            originals[path] = saved
        else:
            originals[path] = None
    moved = []
    written = []
    try:
        for path, (data, mode) in writes.items():
            atomic_write(path, data, mode)
            written.append(path)
        # Remove the previous plugins from discovery only after the new
        # configuration and shortcut destinations are ready.
        for path in moves:
            saved = backup / "removed" / path.relative_to(home_dir)
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(path), str(saved))
            moved.append((path, saved))
        (backup / "migration.json").write_text(json.dumps({
            "replacedPlugins": sorted(OLD_IDS),
            "changedFiles": [str(path) for path in writes],
            "archivedFiles": [str(path) for path in moves],
        }, ensure_ascii=False, indent=2) + "\n")
    except Exception:
        for path, saved in reversed(moved):
            shutil.move(str(saved), str(path))
        for path in reversed(written):
            saved = originals[path]
            if saved is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write(path, saved.read_bytes(), saved.stat().st_mode & 0o777)
        raise
    print(f"Previous Island removed from installed plugins. Backup: {backup}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home(), help="Configuration owner (for isolated tests)")
    parser.add_argument("--state-home", type=Path, help="Backup state directory")
    args = parser.parse_args()
    state_dir = args.state_home or Path(os.environ.get("XDG_STATE_HOME") or str(args.home / ".local/state"))
    try:
        migrate(args.home, state_dir)
    except (OSError, ValueError, TypeError) as error:
        parser.exit(1, f"Island migration failed: {error}\n")
