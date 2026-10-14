#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
prefix="${PREFIX:-$HOME/.local}"
stage="${DESTDIR:-}"
if [[ ! -x dist/linux/bin/ToastMonitor ]]; then ./scripts/build-app.sh; fi
install -Dm755 dist/linux/bin/ToastMonitor "$stage$prefix/bin/ToastMonitor"
if [[ -d dist/linux/lib ]]; then
  mkdir -p "$stage$prefix/lib"
  cp -a dist/linux/lib/. "$stage$prefix/lib/"
fi
install -Dm644 data/io.github.yeyebbc.ToastMonitor.desktop "$stage$prefix/share/applications/io.github.yeyebbc.ToastMonitor.desktop"
# Desktop launchers do not inherit interactive shell PATH.
python3 - "$stage$prefix/share/applications/io.github.yeyebbc.ToastMonitor.desktop" "$prefix/bin/ToastMonitor" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
binary = sys.argv[2].replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
path.write_text(path.read_text().replace('Exec=ToastMonitor', 'Exec="' + binary + '"'))
PY
install -Dm644 artifacts/ToastMonitor-Icon/ToastMonitor-1024.png "$stage$prefix/share/icons/hicolor/512x512/apps/io.github.yeyebbc.ToastMonitor.png"
install -Dm644 data/icons/hicolor/scalable/status/toastmonitor-token-symbolic.svg "$stage$prefix/share/icons/hicolor/scalable/status/toastmonitor-token-symbolic.svg"
extension_source=gnome-extension/toastmonitor@yeyebbc.github.io
extension_target="$stage$prefix/share/gnome-shell/extensions/toastmonitor@yeyebbc.github.io"
mkdir -p "$extension_target"
for source in "$extension_source"/*; do
  install -m644 "$source" "$extension_target/"
done
if [[ "${1:-}" == "--autostart" ]]; then
  config="${XDG_CONFIG_HOME:-$HOME/.config}"
  install -Dm644 data/io.github.yeyebbc.ToastMonitor-autostart.desktop "$stage$config/autostart/io.github.yeyebbc.ToastMonitor.desktop"
  python3 - "$stage$config/autostart/io.github.yeyebbc.ToastMonitor.desktop" "$prefix/bin/ToastMonitor" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
binary = sys.argv[2].replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
path.write_text(path.read_text().replace('Exec=ToastMonitor', 'Exec="' + binary + '"'))
PY
fi
if [[ -z "$stage" ]] && command -v gtk-update-icon-cache >/dev/null; then
  gtk-update-icon-cache -f -t "$prefix/share/icons/hicolor" >/dev/null 2>&1 || true
fi
echo "Installed to $stage$prefix. Launch from your application menu."
