#!/usr/bin/python3
"""Run only in the headless Shell created by smoke-gnome-extension.sh."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import time
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
root = Path(os.environ['TM_EXTENSION_TEST_ROOT'])
captures = Path(os.environ['TM_EXTENSION_CAPTURE_DIR'])
UUID = 'toastmonitor@yeyebbc.github.io'
PRELUDE = "const Main=await import('resource:///org/gnome/shell/ui/main.js');const GLib=(await import('gi://GLib')).default;const e=Main.extensionManager.lookup('" + UUID + "').stateObj;"


def evaluate(code):
    success, result = bus.call_sync('org.gnome.Shell', '/org/gnome/Shell', 'org.gnome.Shell', 'Eval',
        GLib.Variant('(s)', ('(async()=>{' + PRELUDE + code + '})()',)), None,
        Gio.DBusCallFlags.NONE, 15000, None).unpack()
    assert success, result
    return json.loads(result) if result else None


def wait_for(code):
    for attempt in range(100):
        if evaluate('return ' + code + ';'):
            return
        time.sleep(0.1)
    raise AssertionError('Timed out: ' + code)


def capture(name):
    time.sleep(0.3)
    path = json.dumps(str(captures / (name + '.png')))
    evaluate("const Gio=(await import('gi://Gio')).default;const Shell=(await import('gi://Shell')).default;"
             "Main.messageTray._bannerBin.hide();"
             f"const stream=Gio.File.new_for_path({path}).replace(null,false,0,null);"
             "await new Shell.Screenshot().screenshot(false,stream);stream.close(null);return true;")


def status():
    return bus.call_sync('io.github.yeyebbc.ToastMonitor', '/StatusNotifierItem',
        'org.freedesktop.DBus.Properties', 'Get', GLib.Variant('(ss)', ('org.kde.StatusNotifierItem', 'Status')),
        None, Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]


process = None
try:
    # The login helper, rather than the custom test mode, must activate it.
    assert (Path(os.environ['XDG_STATE_HOME']) / 'toastmonitor/gnome-panel-setup-v1').is_file()
    def extension_call(method):
        return bus.call_sync('org.gnome.Shell', '/org/gnome/Shell',
            'org.gnome.Shell.Extensions', method, GLib.Variant('(s)', (UUID,)),
            None, Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]
    info = extension_call('GetExtensionInfo')
    assert info['state'] == 1
    assert info['type'] == 2, info
    assert info['path'] == str(Path(os.environ['XDG_DATA_HOME']) / 'gnome-shell/extensions' / UUID), info
    assert extension_call('DisableExtension')
    subprocess.run(['/usr/bin/python3', os.environ.get('TM_PANEL_SETUP_HELPER', 'scripts/enable-gnome-panel.py'),
                    '--source', os.environ.get('TM_PANEL_EXTENSION_SOURCE', 'gnome-extension/' + UUID)], check=True)
    assert extension_call('GetExtensionInfo')['state'] == 2
    assert extension_call('EnableExtension')
    for attempt in range(100):
        if extension_call('GetExtensionInfo')['state'] == 1:
            break
        time.sleep(0.1)
    assert extension_call('GetExtensionInfo')['state'] == 1
    evaluate('e._indicator.menu.open(); return true;')
    capture('stopped')
    # A legacy app owns the right bus name but exposes no Panel object.
    process = subprocess.Popen(['/usr/bin/python3', '-c',
        "from gi.repository import Gio,GLib;bus=Gio.bus_get_sync(Gio.BusType.SESSION,None);"
        "bus.call_sync('org.freedesktop.DBus','/org/freedesktop/DBus','org.freedesktop.DBus','RequestName',"
        "GLib.Variant('(su)',('io.github.yeyebbc.ToastMonitor',0)),None,Gio.DBusCallFlags.NONE,5000,None);GLib.MainLoop().run()"])
    wait_for("e._status.text.includes('Quit all copies')")
    assert evaluate('return e._claimedOwner;') is None
    capture('legacy-app')
    process.terminate()
    process.wait(timeout=10)
    wait_for('!e._proxy.g_name_owner')
    process = subprocess.Popen([os.environ['TM_SMOKE_BINARY'], '--background'],
                               stdout=(root / 'app.log').open('w'), stderr=subprocess.STDOUT)
    wait_for('e._claimedOwner && e._raw && JSON.parse(e._raw).ready')
    assert status() == 'Passive'
    capture('empty-dark')
    with sqlite3.connect(os.environ['TM_DATABASE_PATH']) as db:
        now = int(time.time())
        for index, tool in enumerate(['codex', 'claude', 'hermes']):
            session = 'panel-fixture-' + tool
            db.execute('INSERT INTO sessions(tool,session_id,title,model,created,updated) VALUES (?,?,?,?,?,?)',
                       (tool, session, 'Synthetic panel fixture', 'test-model', now, now))
            db.execute('INSERT INTO turns(tool,session_id,model,ts,input_tokens,output_tokens,cache_read,cost,cost_quality,event_id) VALUES (?,?,?,?,?,?,?,?,?,?)',
                       (tool, session, 'gpt-5.4' if tool == 'codex' else 'claude-opus-4-6', now, 1234567 + index * 100000, 54321, 500000, 2.34, 'estimated', session))
    wait_for("JSON.parse(e._raw).sources.length === 3")
    capture('usage-dark')
    # All four popup periods use their own totals, not a renamed Today snapshot.
    for period in ['week', 'month', 'all', 'today']:
        evaluate(f'e._periodButtons.get("{period}").emit("clicked",1);return true;')
        assert evaluate('return e._tokens.text;') == evaluate('return e._data.periods.find(p=>p.id===e._period).tokens;')
    # Opening Settings preserves a separate Dashboard window and its navigation.
    evaluate('e._open("Preferences");return true;')
    wait_for('global.get_window_actors().some(a=>a.meta_window.get_title()==="ToastMonitor Settings")')
    evaluate('e._open("Analysis");return true;')
    wait_for('global.get_window_actors().some(a=>a.meta_window.get_title()==="ToastMonitor Dashboard")')
    assert evaluate('return global.get_window_actors().filter(a=>a.meta_window.get_title().startsWith("ToastMonitor ")).length;') == 2
    # Hide both native windows so subsequent popup captures are unambiguous.
    evaluate('for(const a of global.get_window_actors()) if(a.meta_window.get_title().startsWith("ToastMonitor ")) a.meta_window.delete(global.get_current_time());e._indicator.menu.open();return true;')
    # Real keyboard input on the private compositor: Escape, then Enter on the indicator.
    evaluate("const Clutter=(await import('gi://Clutter')).default;globalThis.tmKeyboard=Clutter.get_default_backend().get_default_seat().create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);"
             "tmKeyboard.notify_keyval(0,Clutter.KEY_Escape,Clutter.KeyState.PRESSED);tmKeyboard.notify_keyval(0,Clutter.KEY_Escape,Clutter.KeyState.RELEASED);return true;")
    wait_for('!e._indicator.menu.isOpen')
    evaluate("const Clutter=(await import('gi://Clutter')).default;e._indicator.grab_key_focus();tmKeyboard.notify_keyval(0,Clutter.KEY_Return,Clutter.KeyState.PRESSED);tmKeyboard.notify_keyval(0,Clutter.KEY_Return,Clutter.KeyState.RELEASED);return true;")
    wait_for('e._indicator.menu.isOpen')
    evaluate("const Clutter=(await import('gi://Clutter')).default;globalThis.tmPointer=Clutter.get_default_backend().get_default_seat().create_virtual_device(Clutter.InputDeviceType.POINTER_DEVICE);"
             "tmPointer.notify_absolute_motion(0,20,500);tmPointer.notify_button(0,1,Clutter.ButtonState.PRESSED);tmPointer.notify_button(0,1,Clutter.ButtonState.RELEASED);return true;")
    wait_for('!e._indicator.menu.isOpen')
    # Exercise the actual panel button callback and error-safe teardown.
    evaluate('e._indicator.menu.open(); e._refresh.emit("clicked",1);return true;')
    wait_for('Boolean(e._refreshTimeout) && e._notice.visible')
    # Live snapshots during the cooldown must preserve refresh feedback.
    evaluate("const d=JSON.parse(e._raw);d.updatedAt++;e._proxy.set_cached_property('Snapshot',new GLib.Variant('s',JSON.stringify(d)));e._read();return true;")
    assert evaluate("return e._notice.visible && e._notice.text.startsWith('Refreshing');")
    capture('refreshing')
    evaluate('e._refresh.emit("clicked",1);return true;')
    wait_for('!e._refreshTimeout')
    assert evaluate('return !e._notice.visible;')
    # An actionable failure survives both the cooldown and subsequent snapshots.
    evaluate("const call=e._call;e._call=(_method,_parameters,done)=>done(new Error('Synthetic refresh failure'));e._refreshNow();e._call=call;return true;")
    wait_for('!e._refreshTimeout')
    evaluate("const d=JSON.parse(e._raw);d.updatedAt++;e._proxy.set_cached_property('Snapshot',new GLib.Variant('s',JSON.stringify(d)));e._read();return true;")
    assert evaluate("return e._notice.visible && e._notice.text.startsWith('Refresh failed');")
    capture('refresh-failed')
    evaluate('e._refreshNow();return true;')
    wait_for('!e._refreshTimeout')
    assert evaluate('return !e._notice.visible;')
    # Long, stale, missing and quota values are synthetic presentation fixtures.
    fixture = evaluate('return JSON.parse(e._raw);')
    fixture['accounts'] = [
        {'id': 'claude', 'title': 'Claude · Weekly', 'value': '42% used', 'detail': 'Resets in 2 days · Updated 10-14 13:04', 'fraction': 0.42},
        {'id': 'codex', 'title': 'Codex · A very long subscription plan name to check wrapping', 'value': '87% used', 'detail': 'Refresh failed · last known quota · Reset pending refresh', 'fraction': 0.87},
        {'id': 'router', 'title': 'OpenRouter · Balance', 'value': '$18.42', 'detail': 'Updated 10-14 13:04'},
        {'id': 'deepseek', 'title': 'DeepSeek · Balance', 'value': '—', 'detail': 'Waiting for account data'},
    ]
    raw = json.dumps(json.dumps(fixture))
    evaluate(f"e._proxy.set_cached_property('Snapshot',new GLib.Variant('s',{raw}));e._read();return true;")
    capture('accounts-dark')
    # Apply the stock GNOME light stylesheet, preserving the extension stylesheet.
    css = subprocess.check_output(['gresource', 'extract', '/usr/share/gnome-shell/gnome-shell-theme.gresource',
                                    '/org/gnome/shell/theme/gnome-shell-light.css'])
    theme = root / 'gnome-shell-light.css'
    theme.write_bytes(css)
    evaluate(f'Main.setThemeStylesheet({json.dumps(str(theme))});Main.loadTheme();return true;')
    capture('accounts-light')
    evaluate("const St=(await import('gi://St')).default;const Pango=(await import('gi://Pango')).default;St.ThemeContext.get_for_stage(global.stage).set_font(Pango.FontDescription.from_string('Sans 14'));return true;")
    capture('large-text')
    evaluate('e._scroll.vscroll.adjustment.value=e._scroll.vscroll.adjustment.upper;return true;')
    capture('accounts-scrolled')
    # Disable/re-enable through the real lifecycle; app keeps collecting.
    evaluate('e.disable();return true;')
    for attempt in range(50):
        if status() == 'Active':
            break
        time.sleep(0.1)
    assert status() == 'Active'
    evaluate('e.enable();return true;')
    wait_for('e._claimedOwner && e._raw && JSON.parse(e._raw).ready')
    assert status() == 'Passive'
    process.terminate()
    process.wait(timeout=10)
    wait_for('!e._proxy.g_name_owner')
    assert evaluate('return e._scroll.visible;') is False
    # Restart while extension stays enabled: the startup registration race must recover.
    process = subprocess.Popen([os.environ['TM_SMOKE_BINARY'], '--background'],
                               stdout=(root / 'restarted-app.log').open('w'), stderr=subprocess.STDOUT)
    wait_for('e._claimedOwner && e._raw && JSON.parse(e._raw).ready')
    assert status() == 'Passive'
    evaluate('e._quitButton.emit("clicked",1);return true;')
    process.wait(timeout=10)
    wait_for('!e._proxy.g_name_owner')
    evaluate('e.disable(); return true;')
    print('Extension enabled, claimed tray, rendered data/themes/quotas, handled keyboard/click-away, and recovered across app restart.')
finally:
    if process and process.poll() is None:
        process.terminate()
        process.wait(timeout=10)
