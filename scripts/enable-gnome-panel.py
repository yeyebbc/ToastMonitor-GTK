#!/usr/bin/python3
"""Enable the bundled panel once, in the user's GNOME login session."""
import argparse
import json
import os
from pathlib import Path
import sys
import time

from gi.repository import Gio, GLib

UUID = 'toastmonitor@yeyebbc.github.io'
DESTINATION = 'org.gnome.Shell'
OBJECT = '/org/gnome/Shell'
INTERFACE = 'org.gnome.Shell.Extensions'


def install_extension(source, data_home):
    source = Path(source)
    if json.loads((source / 'metadata.json').read_text()).get('uuid') != UUID:
        raise RuntimeError('The bundled panel has invalid metadata.')
    target = Path(data_home) / 'gnome-shell/extensions' / UUID
    if target.is_symlink():
        raise RuntimeError('The user panel directory is a symbolic link; leaving it unchanged.')
    target.mkdir(parents=True, exist_ok=True)
    # Install metadata last so a new directory is not discovered half-written.
    for name in ('extension.js', 'stylesheet.css', 'toastmonitor-token-symbolic.svg', 'toastmonitor-chart-symbolic.svg', 'metadata.json'):
        content = (source / name).read_bytes()
        destination = target / name
        if destination.is_file() and destination.read_bytes() == content:
            continue
        temporary = target / (name + '.new')
        temporary.write_bytes(content)
        temporary.chmod(0o644)
        temporary.replace(destination)
    return target


def setup(state_home, settings, call, pause=time.sleep):
    marker = Path(state_home) / 'toastmonitor/gnome-panel-setup-v1'
    if marker.exists():
        return

    def remember():
        marker.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        marker.write_text('First-login panel setup completed.\n')

    # An explicit opt-out, including the global extensions switch, wins.
    if (UUID in settings.get_strv('disabled-extensions') or
            settings.get_boolean('disable-user-extensions')):
        remember()
        return

    for attempt in range(20):
        info = call('GetExtensionInfo', GLib.Variant('(s)', (UUID,)))[0]
        if info:
            break
        pause(0.25)
    else:
        raise RuntimeError('GNOME has not discovered the bundled panel; log out and back in.')

    state = info.get('state')
    if state == 4:
        raise RuntimeError('The bundled panel does not support this GNOME Shell version.')
    if state != 1:
        enabled = call('EnableExtension', GLib.Variant('(s)', (UUID,)))[0]
        if not enabled:
            raise RuntimeError('GNOME declined to enable the bundled panel.')
        for attempt in range(40):
            info = call('GetExtensionInfo', GLib.Variant('(s)', (UUID,)))[0]
            if info.get('state') == 1:
                break
            if info.get('state') in (3, 4, 99):
                raise RuntimeError(info.get('error') or 'The bundled panel could not start.')
            pause(0.25)
        else:
            raise RuntimeError('Timed out waiting for the bundled panel to start.')
    remember()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install-only', action='store_true', help='Install for this user before Shell starts')
    parser.add_argument('--source', type=Path, help='Bundled extension source directory')
    arguments = parser.parse_args()
    source = arguments.source or Path(__file__).resolve().parents[2] / 'share/toastmonitor/gnome-extension'
    state_home = os.environ.get('XDG_STATE_HOME') or str(Path.home() / '.local/state')
    data_home = os.environ.get('XDG_DATA_HOME') or str(Path.home() / '.local/share')
    try:
        install_extension(source, data_home)
    except (OSError, ValueError, RuntimeError) as error:
        print(f'ToastMonitor panel installation: {error}', file=sys.stderr)
        return 1
    if arguments.install_only:
        # Initialization-phase autostart waits for registration. Register only
        # after copying, so Shell cannot scan a missing or half-written panel.
        startup_id = os.environ.get('DESKTOP_AUTOSTART_ID')
        if startup_id:
            try:
                Gio.bus_get_sync(Gio.BusType.SESSION, None).call_sync(
                    'org.gnome.SessionManager', '/org/gnome/SessionManager',
                    'org.gnome.SessionManager', 'RegisterClient',
                    GLib.Variant('(ss)', ('io.github.yeyebbc.ToastMonitor-panel-install', startup_id)),
                    None, Gio.DBusCallFlags.NO_AUTO_START, 5000, None)
            except GLib.Error as error:
                print(f'ToastMonitor panel login registration: {error}', file=sys.stderr)
                return 1
        return 0
    if (Path(state_home) / 'toastmonitor/gnome-panel-setup-v1').exists():
        return 0
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

        def call(method, arguments):
            return bus.call_sync(DESTINATION, OBJECT, INTERFACE, method, arguments,
                                 None, Gio.DBusCallFlags.NO_AUTO_START, 5000, None).unpack()

        setup(state_home, Gio.Settings.new('org.gnome.shell'), call)
    except (GLib.Error, OSError, RuntimeError) as error:
        print(f'ToastMonitor panel setup: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
