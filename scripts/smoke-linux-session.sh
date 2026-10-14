#!/usr/bin/env bash
set -euo pipefail
smoke_dir=$(mktemp -d)
app_pid=""
cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then kill "$app_pid"; fi
}
trap cleanup EXIT
export TM_TEST_MODE=1
export TM_DEBUG=1
export TM_DATABASE_PATH="$smoke_dir/usage.db"
export XDG_DATA_HOME="$smoke_dir/data"
export GSK_RENDERER=cairo
export GTK_A11Y=none
export GIO_USE_VFS=local
export GSETTINGS_BACKEND=memory
export GTK_USE_PORTAL=0
export ADW_DISABLE_PORTAL=1
export XDG_RUNTIME_DIR="$smoke_dir/runtime"
mkdir -m 700 "$XDG_RUNTIME_DIR"
export TM_SCREENSHOT_PATH="$smoke_dir/window.png"
"$TM_SMOKE_BINARY" > "$smoke_dir/app.log" 2>&1 &
app_pid=$!
destination="org.kde.StatusNotifierItem-$app_pid-1"
for attempt in {1..300}; do
  if timeout 2 gdbus call --session --dest "$destination" --object-path /StatusNotifierItem \
      --method org.freedesktop.DBus.Properties.Get org.kde.StatusNotifierItem Title > "$smoke_dir/title" 2>/dev/null; then break; fi
  if ! kill -0 "$app_pid" 2>/dev/null; then cat "$smoke_dir/app.log"; exit 1; fi
  sleep 0.1
done
timeout 5 gdbus call --session --dest "$destination" --object-path /StatusNotifierItem \
  --method org.freedesktop.DBus.Properties.GetAll org.kde.StatusNotifierItem > "$smoke_dir/properties"
grep -q "toastmonitor-token-symbolic" "$smoke_dir/properties"
timeout 5 gdbus call --session --dest "$destination" --object-path /StatusNotifierItem \
  --method org.freedesktop.DBus.Properties.Get org.kde.StatusNotifierItem IconThemePath > "$smoke_dir/icon-path"
python3 - "$smoke_dir/icon-path" <<'PY'
import re
import sys
from pathlib import Path
path = re.search(r"'([^']+)'", Path(sys.argv[1]).read_text()).group(1)
assert (Path(path) / 'toastmonitor-token-symbolic.svg').is_file(), path
PY
grep -q "/MenuBar" "$smoke_dir/properties"
gdbus call --session --dest "$destination" --object-path /MenuBar \
  --method com.canonical.dbusmenu.GetLayout 0 1 '[]' > "$smoke_dir/menu"
grep -q "Refresh Now" "$smoke_dir/menu"
grep -q "Quit ToastMonitor" "$smoke_dir/menu"
# Another process activates the existing primary instance and exits.
timeout 10 "$TM_SMOKE_BINARY"
if [[ "${TM_PREVIEW_PAGE:-}" == "Preferences" ]]; then
  gdbus call --session --dest "$destination" --object-path /StatusNotifierItem \
    --method org.kde.StatusNotifierItem.SecondaryActivate 0 0 >/dev/null
else
  gdbus call --session --dest "$destination" --object-path /StatusNotifierItem \
    --method org.kde.StatusNotifierItem.Activate 0 0 >/dev/null
fi
# Foundation/Dispatch completions must be serviced by the GLib loop.
for attempt in {1..100}; do
  gdbus call --session --dest "$destination" --object-path /StatusNotifierItem \
    --method org.freedesktop.DBus.Properties.Get org.kde.StatusNotifierItem Title > "$smoke_dir/title"
  if grep -q "<'0'>" "$smoke_dir/title" && [[ -s "$smoke_dir/window.png" ]]; then break; fi
  sleep 0.1
done
grep -q "<'0'>" "$smoke_dir/title"
test -s "$smoke_dir/window.png"
/usr/bin/python3 scripts/test-panel-client.py
gdbus call --session --dest "$destination" --object-path /MenuBar \
  --method com.canonical.dbusmenu.Event 6 clicked '<0>' 0 >/dev/null
for attempt in {1..100}; do
  if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
  sleep 0.1
done
if kill -0 "$app_pid" 2>/dev/null; then cat "$smoke_dir/app.log"; echo "Quit did not stop the app" >&2; exit 1; fi
wait "$app_pid"
app_pid=""
echo "Tray, DBusMenu, single instance, live refresh, screenshot and quit passed. Artifacts: $smoke_dir"
