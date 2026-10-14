#!/usr/bin/python3
"""Verify first-login setup never undoes opt-outs or records failed activation."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('panel_setup', Path(__file__).with_name('enable-gnome-panel.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Settings:
    def __init__(self, disabled=(), globally_disabled=False):
        self.disabled = disabled
        self.globally_disabled = globally_disabled

    def get_strv(self, key):
        assert key == 'disabled-extensions'
        return self.disabled

    def get_boolean(self, key):
        assert key == 'disable-user-extensions'
        return self.globally_disabled


class SetupTests(unittest.TestCase):
    def test_opt_out_and_global_switch_are_respected(self):
        for settings in (Settings([module.UUID]), Settings(globally_disabled=True)):
            with self.subTest(settings=settings), tempfile.TemporaryDirectory() as home:
                def unexpected(*args):
                    self.fail('Opt-out must not call the Shell')
                module.setup(home, settings, unexpected)
                self.assertTrue((Path(home) / 'toastmonitor/gnome-panel-setup-v1').exists())

    def test_missing_incompatible_and_failed_extensions_retry_next_login(self):
        for info, accepted in (({}, True), ({'state': 4}, True),
                               ({'state': 2}, False), ({'state': 3, 'error': 'fixture failure'}, True)):
            with self.subTest(info=info), tempfile.TemporaryDirectory() as home:
                def call(method, args):
                    return (accepted,) if method == 'EnableExtension' else (info,)
                with self.assertRaises(RuntimeError):
                    module.setup(home, Settings(), call, pause=lambda _: None)
                self.assertFalse((Path(home) / 'toastmonitor/gnome-panel-setup-v1').exists())

    def test_first_login_only(self):
        with tempfile.TemporaryDirectory() as home:
            state = {'value': 2}
            methods = []
            def call(method, args):
                methods.append(method)
                if method == 'EnableExtension':
                    state['value'] = 1
                    return (True,)
                return ({'state': state['value']},)
            module.setup(home, Settings(), call, pause=lambda _: None)
            self.assertEqual(methods.count('EnableExtension'), 1)
            state['value'] = 2  # User disables the extension later.
            module.setup(home, Settings(), call, pause=lambda _: None)
            self.assertEqual(methods.count('EnableExtension'), 1)
            self.assertEqual(state['value'], 2)


if __name__ == '__main__':
    unittest.main()
