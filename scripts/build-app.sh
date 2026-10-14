#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift_bin="${SWIFT:-swift}"
if ! command -v "$swift_bin" >/dev/null; then
  echo "Swift is required. Set PATH or SWIFT to your Linux toolchain." >&2
  exit 1
fi
pkg-config --atleast-version=4.14 gtk4
pkg-config --atleast-version=1.5 libadwaita-1
pkg-config --exists sqlite3 libsecret-1
"$swift_bin" build -c release -j "${SWIFT_JOBS:-4}"
binary_dir=$("$swift_bin" build -c release --show-bin-path)
install -Dm755 "$binary_dir/ToastMonitor" dist/linux/bin/ToastMonitor
install -Dm644 data/io.github.yeyebbc.ToastMonitor.desktop dist/linux/share/applications/io.github.yeyebbc.ToastMonitor.desktop
install -Dm644 artifacts/ToastMonitor-Icon/ToastMonitor-1024.png dist/linux/share/icons/hicolor/512x512/apps/io.github.yeyebbc.ToastMonitor.png
install -Dm644 data/icons/hicolor/scalable/status/toastmonitor-token-symbolic.svg dist/linux/share/icons/hicolor/scalable/status/toastmonitor-token-symbolic.svg
extension_dir=dist/linux/share/gnome-shell/extensions/toastmonitor@yeyebbc.github.io
mkdir -p "$extension_dir"
for source in gnome-extension/toastmonitor@yeyebbc.github.io/*; do
  install -m644 "$source" "$extension_dir/"
done
# Swift executables use toolchain runtime libraries on Linux. Ship those for
# machines which have the GNOME libraries but no Swift development toolchain.
ldd "$binary_dir/ToastMonitor" | while read -r name arrow path rest; do
  case "$path" in
    */swift/linux/*) install -Dm755 "$path" "dist/linux/lib/toastmonitor/$(basename "$path")" ;;
  esac
done
printf '%s\n' "Built dist/linux/bin/ToastMonitor"
