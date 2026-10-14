#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
project_dir="$PWD"

for tool in dpkg-deb dpkg-shlibdeps dpkg-architecture python3; do
  command -v "$tool" >/dev/null || { echo "$tool is required to build a Debian package." >&2; exit 1; }
done
version="${TM_VERSION:-1.0.4}"
revision="${TM_DEB_REVISION:-1}"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "TM_VERSION must be numeric" >&2; exit 1; }
[[ "$revision" =~ ^[0-9]+$ ]] || { echo "TM_DEB_REVISION must be numeric" >&2; exit 1; }
maintainer="${TM_DEB_MAINTAINER:-ToastMonitor-GTK contributors}"
[[ -n "$maintainer" && "$maintainer" != *$'\n'* && "$maintainer" != *$'\r'* ]] || {
  echo "TM_DEB_MAINTAINER must be a single non-empty line" >&2; exit 1;
}
architecture=$(dpkg-architecture -qDEB_HOST_ARCH)

./scripts/build-app.sh
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
package_dir="$work_dir/package"
mkdir -p "$package_dir/DEBIAN"
DESTDIR="$package_dir" PREFIX=/usr ./scripts/install-linux.sh
install -Dm755 scripts/enable-gnome-panel.py "$package_dir/usr/libexec/toastmonitor/enable-gnome-panel"
install -Dm644 data/io.github.yeyebbc.ToastMonitor-panel-setup.desktop "$package_dir/etc/xdg/autostart/io.github.yeyebbc.ToastMonitor-panel-setup.desktop"
install -Dm644 LICENSE "$package_dir/usr/share/doc/toastmonitor/copyright"
gzip -n -9 -c README.md > "$package_dir/usr/share/doc/toastmonitor/README.md.gz"
# Keep the notices for the Swift runtimes and compiled package dependencies.
swift_license=$("${SWIFT:-swift}" -print-target-info | python3 -c '
import json, pathlib, sys
root = pathlib.Path(json.load(sys.stdin)["paths"]["runtimeResourcePath"]).parent.parent
print(root / "share/swift/LICENSE.txt")
')
if [[ -f "$swift_license" ]]; then
  install -Dm644 "$swift_license" "$package_dir/usr/share/doc/toastmonitor/licenses/swift/LICENSE.txt"
fi
shopt -s nullglob
for checkout in .build/checkouts/*; do
  for notice in "$checkout"/LICENSE* "$checkout"/NOTICE* "$checkout"/COPYING*; do
    [[ -f "$notice" ]] || continue
    install -Dm644 "$notice" "$package_dir/usr/share/doc/toastmonitor/licenses/$(basename "$checkout")/$(basename "$notice")"
  done
done
shopt -u nullglob

# Analyze the bundled runtimes too: their indirect system dependencies are
# needed on a machine without Swift. Private libraries have no dpkg metadata.
mkdir -p "$work_dir/debian"
cat > "$work_dir/debian/control" <<EOF
Source: toastmonitor
Section: utils
Priority: optional
Maintainer: $maintainer

Package: toastmonitor
Architecture: any
Description: Native GNOME monitor for AI usage and account quotas
EOF
elf_files=("-e$package_dir/usr/bin/ToastMonitor")
for library in "$package_dir"/usr/lib/toastmonitor/*.so; do
  elf_files+=("-e$library")
done
dependencies=$(cd "$work_dir" && dpkg-shlibdeps -O --ignore-missing-info \
  "-l$package_dir/usr/lib/toastmonitor" "${elf_files[@]}")
dependencies=$(python3 - "$dependencies" <<'PY'
import sys
line = next(line for line in sys.argv[1].splitlines() if line.startswith('shlibs:Depends='))
deps = line.removeprefix('shlibs:Depends=').split(', ')
deps = [dep for dep in deps if dep.split(' ')[0] not in ('libgtk-4-1', 'libadwaita-1-0')]
deps.extend(['libgtk-4-1 (>= 4.14)', 'libadwaita-1-0 (>= 1.5)', 'zstd', 'python3', 'python3-gi'])
print(', '.join(deps))
PY
)
installed_size=$(du -sk "$package_dir/usr" | cut -f1)
cat > "$package_dir/DEBIAN/control" <<EOF
Package: toastmonitor
Version: $version-$revision
Section: utils
Priority: optional
Architecture: $architecture
Maintainer: $maintainer
Installed-Size: $installed_size
Depends: $dependencies
Recommends: gnome-keyring
Suggests: gnome-shell-extension-appindicator
Homepage: https://github.com/yeyebbc/ToastMonitor-GTK
Description: Native GNOME monitor for AI usage and account quotas
 Collects local AI tool usage into SQLite and provides token totals,
 daily analysis, recent sessions, and optional account quota monitoring.
 Uses GTK4 and libadwaita with GNOME Secret Service for credentials.
EOF
chmod 755 "$package_dir/DEBIAN"
chmod 644 "$package_dir/DEBIAN/control"
mkdir -p "$project_dir/dist/release"
output="$project_dir/dist/release/toastmonitor_${version}-${revision}_${architecture}.deb"
dpkg-deb --root-owner-group -Zxz --build "$package_dir" "$output"
(cd "$project_dir/dist/release" && sha256sum "$(basename "$output")" > "$(basename "$output").sha256")
printf '%s\n' "$output"
