#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --session ]]; then
  exec dbus-run-session --config-file scripts/smoke-linux-bus.conf -- bash "$0" --session
fi
# Shell needs a system-bus connection even without a real login session. Reuse
# this private bus so containers work and tests never contact host services.
export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
smoke_dir=$(mktemp -d)
shell_pid='' app_pid=''
cleanup() {
  if [[ -n "$app_pid" ]]; then kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; fi
  if [[ -n "$shell_pid" ]]; then kill "$shell_pid" 2>/dev/null || true; wait "$shell_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
uuid=toastmonitor@yeyebbc.github.io
export TM_EXTENSION_CAPTURE_DIR="${TM_EXTENSION_CAPTURE_DIR:-$smoke_dir/captures}"
mkdir -p "$smoke_dir/data/gnome-shell/extensions" "$smoke_dir/system/gnome-shell/modes" "$smoke_dir/config" "$smoke_dir/runtime" "$TM_EXTENSION_CAPTURE_DIR"
chmod 700 "$smoke_dir/runtime"
cp -a "gnome-extension/$uuid" "$smoke_dir/data/gnome-shell/extensions/"
# This driver exists only inside the private test compositor and is never packaged.
mkdir -p "$smoke_dir/data/gnome-shell/extensions/toastmonitor-test@local"
cat > "$smoke_dir/data/gnome-shell/extensions/toastmonitor-test@local/metadata.json" <<'JSON'
{"uuid":"toastmonitor-test@local","name":"Isolated test driver","description":"Test only","shell-version":["46"],"session-modes":["user","toastmonitor-test"]}
JSON
cat > "$smoke_dir/data/gnome-shell/extensions/toastmonitor-test@local/extension.js" <<'JS'
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
export default class TestDriver extends Extension {
    enable() { global.context.unsafe_mode = true; }
    disable() { global.context.unsafe_mode = false; }
}
JS
cat > "$smoke_dir/system/gnome-shell/modes/toastmonitor-test.json" <<'JSON'
{"parentMode":"user","hasOverview":false,"showWelcomeDialog":false,"showCalendarEvents":false,"components":[],"enabledExtensions":["toastmonitor-test@local"]}
JSON
export XDG_DATA_HOME="$smoke_dir/data" XDG_CONFIG_HOME="$smoke_dir/config" XDG_STATE_HOME="$smoke_dir/state" XDG_RUNTIME_DIR="$smoke_dir/runtime" XDG_DATA_DIRS="$smoke_dir/system:/usr/share"
export GSETTINGS_BACKEND=memory GTK_A11Y=none LIBGL_ALWAYS_SOFTWARE=1
export TM_TEST_MODE=1 TM_DATABASE_PATH="$smoke_dir/usage.db" GSK_RENDERER=cairo
export TM_SMOKE_BINARY="${TM_SMOKE_BINARY:-$PWD/.build/debug/ToastMonitor}"
export TM_EXTENSION_TEST_ROOT="$smoke_dir"
gnome-shell --headless --virtual-monitor 1280x900 --wayland --no-x11 --mode toastmonitor-test > "$smoke_dir/shell.log" 2>&1 &
shell_pid=$!
for attempt in {1..120}; do
  if gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.gnome.Shell.Eval '1+1' > "$smoke_dir/ready" 2>/dev/null && grep -q true "$smoke_dir/ready"; then break; fi
  if ! kill -0 "$shell_pid" 2>/dev/null; then cat "$smoke_dir/shell.log"; exit 1; fi
  sleep 0.25
done
grep -q true "$smoke_dir/ready"
/usr/bin/python3 "${TM_PANEL_SETUP_HELPER:-scripts/enable-gnome-panel.py}"
export WAYLAND_DISPLAY=wayland-0 GDK_BACKEND=wayland
/usr/bin/python3 scripts/test-gnome-extension.py
if grep -E 'JS ERROR|Extension .*toastmonitor.*Error|Theme parsing error' "$smoke_dir/shell.log"; then exit 1; fi
echo "GNOME Shell popup, keyboard, click-away, live update, reconnect and cleanup passed. Artifacts: $smoke_dir"
