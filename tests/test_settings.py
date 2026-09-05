import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import settings
import menu_integration
spec = importlib.util.spec_from_file_location('settings_ui', ROOT/'settings-ui.py')
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name)
        self.old = settings.CONFIG, settings.STATE, settings.ERROR, menu_integration.MENU
        settings.CONFIG = self.path/'taskbar.json'
        settings.STATE = self.path/'state'
        settings.ERROR = ''
        menu_integration.MENU = self.path/'menu.jsonc'
        # Avoid migration from the user's shell file.
        settings.STATE.mkdir()
        settings.atomic_write(settings.CONFIG, settings.DEFAULTS)

    def tearDown(self):
        settings.CONFIG, settings.STATE, settings.ERROR, menu_integration.MENU = self.old
        self.temp.cleanup()

    def test_every_setting_has_help_and_schema(self):
        data = ui.read()
        for section, values in data['config'].items():
            if section == 'schemaVersion':
                continue
            for key in values:
                path = section+'.'+key
                self.assertTrue(data['meta']['fields'][path]['description'].strip(), path)
                self.assertIn(key, data['schema']['properties'][section]['properties'])

    def test_invalid_edit_retains_last_valid_configuration(self):
        settings.update_settings({'bar': {'iconSize': 23}})
        settings.CONFIG.write_text('{ broken')
        self.assertEqual(settings.load_settings()['bar']['iconSize'], 23)
        self.assertTrue(settings.ERROR)
        with self.assertRaises(ValueError):
            settings.update_settings({'bar': {'iconSize': 24}})
        self.assertEqual(settings.CONFIG.read_text(), '{ broken')

    def test_apply_preserves_unrelated_changes_and_rejects_conflicts(self):
        settings.update_settings({'switcher': {'backgroundReveal': .7}})
        ui.apply({'bar.iconSize': {'before': 17, 'after': 23}})
        self.assertEqual(settings.load_settings()['switcher']['backgroundReveal'], .7)
        before = settings.CONFIG.read_text()
        with self.assertRaises(ValueError):
            ui.apply({'switcher.backgroundReveal': {'before': .62, 'after': .8}})
        self.assertEqual(settings.CONFIG.read_text(), before)

    def test_invalid_values_and_shortcuts_never_write(self):
        settings.load_settings()
        before = settings.CONFIG.read_text()
        for path, old, new in [('bar.iconSize',17,-1),
                               ('keyboard.minimize','SUPER + M','SUPER + MissingKeyName'),
                               ('workspace.modes',{}, {'1':'floating'})]:
            with self.assertRaises(ValueError):
                ui.apply({path: {'before':old,'after':new}})
            self.assertEqual(settings.CONFIG.read_text(), before)

    def test_menu_is_idempotent_and_removal_preserves_customizations(self):
        for original in ['// { leading comment\n{\n}\n',
                         '{\n // "items": { example\n "items": {"setup.mine":{"label":"Mine"}}\n}\n']:
            menu_integration.MENU.write_text(original)
            menu_integration.sync()
            installed = menu_integration.MENU.read_text()
            menu_integration.sync()
            self.assertEqual(menu_integration.MENU.read_text(), installed)
            data = menu_integration.parsed(installed)
            self.assertIn('setup.legion-taskbar', data.get('items',data))
            menu_integration.sync(False)
            self.assertEqual(menu_integration.MENU.read_text(), original)

    def test_menu_does_not_replace_an_unowned_entry(self):
        original = '{"setup.legion-taskbar":{"label":"Custom","action":"true"}}'
        menu_integration.MENU.write_text(original)
        menu_integration.sync()
        self.assertEqual(menu_integration.MENU.read_text(), original)


if __name__ == '__main__':
    unittest.main()
