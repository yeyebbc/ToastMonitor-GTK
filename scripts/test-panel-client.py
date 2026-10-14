#!/usr/bin/python3
"""Integration check; run only against the private smoke-test session bus."""
import json
import os
import time

from gi.repository import Gio, GLib

BUS = 'io.github.yeyebbc.ToastMonitor'
PATH = '/io/github/yeyebbc/ToastMonitor/Panel'
IFACE = 'io.github.yeyebbc.ToastMonitor.Panel'
flags = Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
owner = Gio.DBusConnection.new_for_address_sync(os.environ['DBUS_SESSION_BUS_ADDRESS'], flags, None, None)
observer = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def call(connection, path, interface, method, parameters=None, destination=BUS):
    return connection.call_sync(destination, path, interface, method, parameters, None,
                                Gio.DBusCallFlags.NO_AUTO_START, 5000, None).unpack()


def status():
    return call(observer, '/StatusNotifierItem', 'org.freedesktop.DBus.Properties', 'Get',
                GLib.Variant('(ss)', ('org.kde.StatusNotifierItem', 'Status')))[0]


for attempt in range(50):
    raw = call(observer, PATH, 'org.freedesktop.DBus.Properties', 'Get',
               GLib.Variant('(ss)', (IFACE, 'Snapshot')))[0]
    snapshot = json.loads(raw)
    if snapshot.get('ready'):
        break
    time.sleep(0.1)
assert snapshot['version'] == 1 and snapshot['ready'], snapshot
assert snapshot['tokens'] == '0' and snapshot['sources'] == [], snapshot
assert 'credentials' not in snapshot and 'sessions' not in snapshot
assert status() == 'Active'
call(owner, PATH, IFACE, 'SetPanelActive', GLib.Variant('(b)', (True,)))
assert status() == 'Passive', 'Companion extension must hide the fallback tray'
call(observer, PATH, IFACE, 'SetPanelActive', GLib.Variant('(b)', (False,)))
assert status() == 'Passive', 'Another client must not release the extension lease'
call(owner, PATH, IFACE, 'SetExpanded', GLib.Variant('(b)', (True,)))
call(owner, PATH, IFACE, 'Refresh')
for page in ['Overview', 'Analysis', 'Plans', 'Sessions', 'Preferences']:
    call(owner, PATH, IFACE, 'Open', GLib.Variant('(s)', (page,)))
try:
    call(owner, PATH, IFACE, 'Open', GLib.Variant('(s)', ('invalid',)))
    raise AssertionError('Unknown page was accepted')
except GLib.Error as error:
    assert 'InvalidArgs' in str(error), error
call(owner, PATH, IFACE, 'SetExpanded', GLib.Variant('(b)', (False,)))
call(owner, PATH, IFACE, 'SetPanelActive', GLib.Variant('(b)', (False,)))
assert status() == 'Active', 'Disable must restore the fallback tray'
call(owner, PATH, IFACE, 'SetPanelActive', GLib.Variant('(b)', (True,)))
owner.close_sync(None)
for attempt in range(50):
    if status() == 'Active':
        break
    time.sleep(0.1)
assert status() == 'Active', 'Shell disconnect must restore the fallback tray'
print('Panel D-Bus payload, navigation, refresh, lease ownership, disable and disconnect passed.')
