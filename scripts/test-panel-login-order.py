#!/usr/bin/python3
"""Check user-panel installation completes before GNOME's WindowManager phase."""
import os, pathlib, signal, subprocess, sys, tempfile, time

repo = pathlib.Path(__file__).resolve().parent.parent
if '--session' not in sys.argv:
    sys.exit(subprocess.call(['dbus-run-session', '--config-file', str(repo / 'scripts/smoke-linux-bus.conf'), '--', 'xvfb-run', '-a', sys.executable, str(pathlib.Path(__file__).resolve()), '--session']))

root = pathlib.Path(tempfile.mkdtemp(prefix='toast-login-order.'))
for name in ('data/gnome-session/sessions', 'data/applications', 'config/gnome-session/sessions', 'autostart', 'runtime'):
    (root / name).mkdir(parents=True, exist_ok=True)
(root / 'runtime').chmod(0o700)
env = dict(os.environ, XDG_DATA_HOME=str(root / 'data'), XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(root / 'runtime'), XDG_DATA_DIRS='/usr/share', XDG_CURRENT_DESKTOP='GNOME', GSETTINGS_BACKEND='memory', DBUS_SYSTEM_BUS_ADDRESS=os.environ['DBUS_SESSION_BUS_ADDRESS'])
(root / 'config/gnome-session/sessions/toast-order.session').write_text('[GNOME Session]\nName=Toast order check\nRequiredComponents=toast-test-wm;\n')
wm = root / 'wm.py'
wm.write_text('''import os,pathlib
from gi.repository import Gio,GLib
p=pathlib.Path(os.environ['XDG_DATA_HOME'])/'gnome-shell/extensions/toastmonitor@yeyebbc.github.io/metadata.json'
assert p.is_file(), 'Panel was not installed before the WindowManager phase'
(p.parents[3]/'order-passed').write_text('User extension existed before WindowManager startup')
bus=Gio.bus_get_sync(Gio.BusType.SESSION,None)
bus.call_sync('org.gnome.SessionManager','/org/gnome/SessionManager','org.gnome.SessionManager','RegisterClient',GLib.Variant('(ss)',('toast-test-wm',os.environ.get('DESKTOP_AUTOSTART_ID',''))),None,Gio.DBusCallFlags.NONE,5000,None)
GLib.MainLoop().run()
''')
(root / 'data/applications/toast-test-wm.desktop').write_text(f'[Desktop Entry]\nType=Application\nName=Test WM\nExec=/usr/bin/python3 {wm}\nX-GNOME-Autostart-Phase=WindowManager\nX-GNOME-Autostart-Notify=true\n')
entry = (repo / 'data/io.github.yeyebbc.ToastMonitor-panel-install.desktop').read_text().replace('Exec=/usr/libexec/toastmonitor/enable-gnome-panel --install-only', f'Exec=/usr/bin/python3 {repo}/scripts/enable-gnome-panel.py --install-only --source {repo}/gnome-extension/toastmonitor@yeyebbc.github.io').replace('TryExec=/usr/libexec/toastmonitor/enable-gnome-panel', 'TryExec=/usr/bin/python3')
(root / 'autostart/install.desktop').write_text(entry)
log = (root / 'session.log').open('w')
process = subprocess.Popen(['gnome-session', '--session=toast-order', '--autostart=' + str(root / 'autostart'), '--disable-acceleration-check', '--debug'], env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
try:
    for _ in range(100):
        if (root / 'data/order-passed').exists():
            print((root / 'data/order-passed').read_text())
            print('Actual gnome-session initialization ordering passed. Artifacts:', root)
            break
        if process.poll() is not None:
            raise RuntimeError('gnome-session stopped: ' + str(root))
        time.sleep(0.2)
    else:
        raise RuntimeError('Initialization ordering timed out: ' + str(root))
finally:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
