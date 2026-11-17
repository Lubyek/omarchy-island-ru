import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[1] / "companion/migrate-legacy.py"
SPEC = importlib.util.spec_from_file_location("legacy_migration", SOURCE)
migration = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(migration)


class LegacyMigrationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.user_dir = self.root / "user"
        self.state = self.user_dir / ".local/state"
        self.config_dir = self.user_dir / ".config/omarchy"
        self.plugins = self.config_dir / "plugins"
        self.hypr = self.user_dir / ".config/hypr"
        self.plugins.mkdir(parents=True)
        self.hypr.mkdir(parents=True)
        self.config = self.config_dir / "shell.json"
        self.settings = self.config_dir / "huesos-island.json"
        self.config.write_text(json.dumps({
            "bar": {"id": "guilhermerisu.island", "layout": {"left": [{"id": "test.keep"}]}},
            "plugins": [{"id": "guilhermerisu.notifications"}, {"id": "test.keep", "value": 7}],
            "disabledPlugins": ["test.disabled", "guilhermerisu.island"],
            "custom": "keep me",
        }))
        (self.config_dir / "island.json").write_text('{"clock24h": false, "motionScale": 2}')
        for plugin_id in migration.OLD_IDS:
            path = self.plugins / plugin_id
            path.mkdir()
            (path / "manifest.json").write_text(json.dumps({"id": plugin_id}))
            (path / "local-edit.txt").write_text("uncommitted work")
        self.old_keys = self.hypr / "island-bindings.lua"
        self.old_keys.write_text('-- format: 2\no.bind("SUPER + J", "Custom", "omarchy-shell guilhermerisu.island toggle")\n')
        self.hyprland = self.hypr / "hyprland.lua"
        self.hyprland.write_text('require("hypr.bindings")\nrequire("default.hypr.require_optional").module("hypr.island-bindings")\n-- keep this\n')
        self.bindings = self.hypr / "bindings.lua"
        self.bindings.write_text('o.bind("SUPER + K", "Island", "omarchy-shell guilhermerisu.island show settings")\no.bind("SUPER + T", "Keep", "my-terminal")\n')
        self.menu = self.config_dir / "extensions/omarchy-menu.jsonc"
        self.menu.parent.mkdir()
        self.menu.write_text('{\n"apps": {"action":"omarchy-shell guilhermerisu.island apps"},\n"custom": {"action":"echo keep me"}\n}\n')

    def run_migration(self):
        migration.migrate(self.user_dir, self.state)

    def test_replaces_plugins_and_preserves_unrelated_configuration(self):
        self.run_migration()
        data = json.loads(self.config.read_text())
        self.assertEqual(data["bar"]["id"], "huesos.island")
        self.assertEqual(data["plugins"], [{"id": "test.keep", "value": 7}])
        self.assertEqual(data["disabledPlugins"], ["test.disabled"])
        self.assertEqual(data["bar"]["layout"]["left"], [{"id": "test.keep"}])
        self.assertEqual(data["custom"], "keep me")
        for plugin_id in migration.OLD_IDS:
            self.assertFalse((self.plugins / plugin_id).exists())
            copies = list(self.state.glob(f"omarchy/backups/*/removed/.config/omarchy/plugins/{plugin_id}/local-edit.txt"))
            self.assertEqual(len(copies), 1)
            self.assertEqual(copies[0].read_text(), "uncommitted work")

    def test_retargets_menu_and_custom_shortcuts(self):
        self.run_migration()
        new_keys = self.hypr / "huesos-island-bindings.lua"
        self.assertIn('SUPER + J', new_keys.read_text())
        self.assertIn('omarchy-shell huesos.island toggle', new_keys.read_text())
        self.assertFalse(self.old_keys.exists())
        self.assertNotIn('hypr.island-bindings', self.hyprland.read_text())
        self.assertIn('-- keep this', self.hyprland.read_text())
        self.assertIn('omarchy-shell huesos.island show settings', self.bindings.read_text())
        self.assertIn('my-terminal', self.bindings.read_text())
        self.assertIn('omarchy-shell huesos.island apps', self.menu.read_text())
        self.assertIn('echo keep me', self.menu.read_text())

    def test_imports_settings_only_when_new_settings_are_absent(self):
        self.run_migration()
        self.assertEqual(json.loads(self.settings.read_text()), {"clock24h": False, "motionScale": 2})
        self.assertTrue((self.config_dir / "island.json").exists())

    def test_existing_fork_preferences_and_keys_are_kept(self):
        self.settings.write_text('{"language":"en"}')
        new_keys = self.hypr / "huesos-island-bindings.lua"
        new_keys.write_text('-- existing fork shortcuts\n')
        self.run_migration()
        self.assertEqual(self.settings.read_text(), '{"language":"en"}')
        self.assertEqual(new_keys.read_text(), '-- existing fork shortcuts\n')

    def test_repeat_run_is_a_noop(self):
        self.run_migration()
        before = {str(p): p.read_bytes() for p in self.user_dir.rglob('*') if p.is_file()}
        self.run_migration()
        after = {str(p): p.read_bytes() for p in self.user_dir.rglob('*') if p.is_file()}
        self.assertEqual(before, after)

    def test_invalid_shell_json_does_not_remove_old_plugin(self):
        self.config.write_text('{not valid json')
        with self.assertRaises(ValueError):
            self.run_migration()
        self.assertEqual(self.config.read_text(), '{not valid json')
        self.assertTrue(self.old_keys.exists())
        self.assertTrue((self.plugins / 'guilhermerisu.island').exists())
        self.assertFalse(self.settings.exists())

    def test_unexpected_plugin_folder_is_left_intact(self):
        manifest = self.plugins / 'guilhermerisu.island/manifest.json'
        manifest.write_text('{"id":"someone.else"}')
        original = self.config.read_bytes()
        with self.assertRaises(ValueError):
            self.run_migration()
        self.assertTrue(manifest.exists())
        self.assertEqual(self.config.read_bytes(), original)

    def test_failed_move_rolls_back_changed_files(self):
        original = self.config.read_bytes()
        original_keys = self.old_keys.read_bytes()
        actual_move = migration.shutil.move
        calls = 0

        def fail_second_move(source, destination):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError('simulated archive failure')
            return actual_move(source, destination)

        with mock.patch.object(migration.shutil, 'move', side_effect=fail_second_move):
            with self.assertRaises(OSError):
                self.run_migration()
        self.assertEqual(self.config.read_bytes(), original)
        self.assertEqual(self.old_keys.read_bytes(), original_keys)
        self.assertFalse(self.settings.exists())
        for plugin_id in migration.OLD_IDS:
            self.assertTrue((self.plugins / plugin_id / 'local-edit.txt').exists())

    def test_clean_install_does_not_create_a_migration_backup(self):
        with tempfile.TemporaryDirectory() as empty:
            target = Path(empty)
            migration.migrate(target, target / 'state')
            self.assertEqual(list(target.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
