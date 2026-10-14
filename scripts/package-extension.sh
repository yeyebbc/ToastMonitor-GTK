#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v gnome-extensions >/dev/null || { echo 'gnome-extensions is required to package the extension.' >&2; exit 1; }
mkdir -p dist/release
gnome-extensions pack --force --extra-source=toastmonitor-token-symbolic.svg \
  --out-dir=dist/release gnome-extension/toastmonitor@yeyebbc.github.io
(cd dist/release && sha256sum toastmonitor@yeyebbc.github.io.shell-extension.zip > toastmonitor@yeyebbc.github.io.shell-extension.zip.sha256)
echo 'Built dist/release/toastmonitor@yeyebbc.github.io.shell-extension.zip'
