#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
mkdir -p dist/release
version="${TM_VERSION:-1.0.7}"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "TM_VERSION must be numeric" >&2; exit 1; }
archive="dist/release/ToastMonitor-${version}-linux-$(uname -m).tar.gz"
tar -czf "$archive" -C dist/linux .
sha256sum "$archive" > "$archive.sha256"
printf '%s\n' "$archive"
