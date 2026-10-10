#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift_bin="${SWIFT:-swift}"
"$swift_bin" build -j 4
export TM_SMOKE_BINARY
TM_SMOKE_BINARY="$("$swift_bin" build --show-bin-path)/ToastMonitor"
exec dbus-run-session --config-file scripts/smoke-linux-bus.conf -- xvfb-run -a bash scripts/smoke-linux-session.sh
