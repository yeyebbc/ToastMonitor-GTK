# ToastMonitor-GTK

**The GNOME/Linux port of [Toast1zz/ToastMonitor](https://github.com/Toast1zz/ToastMonitor)**, the original macOS menu-bar AI usage monitor. This repository adapts its collection and accounting engine to a native GNOME tray application using [adwaita-swift](https://codeberg.org/aparoksha/adwaita-swift), GTK4 and libadwaita.

The original ToastMonitor is developed by Toast and distributed under the MIT license. This port preserves the upstream license and copyright notice. For the macOS application, visit the [original repository](https://github.com/Toast1zz/ToastMonitor); the build in this repository targets Linux.

Collects **Claude Code, Codex, OpenCode, Hermes, Oh My Pi and DeepSeek Harness** logs into one local SQLite database. Retains the original parsers, deduplication, pricing and database migrations.

- **Tray:** today’s token total, tooltip, dashboard, preferences, refresh and quit actions. Closing the window continues collection (1-second foreground / 5-second background scans).
- **Dashboard:** today / 7 days / 30 days / all time, per-tool and per-model totals, daily analysis with CSV export, recent sessions.
- **Accounts:** Claude subscription (opt-in), Codex subscription, OpenCode Go, Command Code, OpenRouter and DeepSeek balances/account spend. Errors retain the last successful quota values.
- **Sources:** local-first; explicitly configured remote feeds for Claude, Codex, OpenCode and Hermes.
- **Privacy:** usage stays local. Credentials use GNOME Secret Service (GNOME Keyring or another compatible provider). No analytics. Protected SQLite backups and redacted exports retain the original recovery safeguards.

## What changed for GNOME

| Area | GNOME port |
|---|---|
| Interface | Two native GTK4/libadwaita windows follow the macOS layouts: Dashboard (Overview, Analysis, Plans, Sessions) and Settings (General, Appearance, Sources, Accounts, Data). |
| Tray | StatusNotifierItem and DBusMenu replace the macOS menu-bar integration. Closing a window hides it while collection continues; Quit stops the app. |
| Appearance | GNOME sets fonts. Settings offers System, Light and Dark appearance plus popup display options. A symbolic token icon follows the tray host's foreground color. |
| Credentials | GNOME Secret Service replaces macOS Keychain. Existing Claude Code and Codex CLI login files are still used. |
| Storage | XDG data directories replace macOS Application Support. SQLite migrations, backups, restore validation and exports are retained. |
| Swift dependencies | OpenCombine and swift-crypto provide Linux-compatible equivalents for Combine and CryptoKit. SQLite, GIO and libsecret use system libraries. |
| Distribution | Linux release archives, desktop entries, optional login autostart and a user-local installer replace macOS app bundles and the built-in updater. |

This is a platform adaptation rather than complete UI feature parity. The macOS font picker, browser-based DeepSeek login automation and updater are not available in the Linux build. DeepSeek credentials can be entered in Settings → Accounts. Historical macOS sources remain in the repository but are excluded from the Linux target.

## Requirements

Linux, Swift **6.0+**, GTK **4.14+**, libadwaita **1.5+**, SQLite and libsecret. The dependency is pinned to adwaita-swift **0.1.0**; upstream main requires an experimental newer Swift toolchain. `Package.resolved` locks transitive dependencies.

Ubuntu 24.04 / Linux Mint 22:

```sh
sudo apt-get update
sudo apt-get install -y libgtk-4-dev libadwaita-1-dev libsqlite3-dev libsecret-1-dev \
  libssl-dev libcurl4-openssl-dev zstd xvfb dbus-x11
```

Clone this port and install Swift from [swift.org](https://www.swift.org/install/linux/). For a Swift 6.0.3 Ubuntu toolchain extracted under `~/dev-tools/`:

```sh
git clone https://github.com/yeyebbc/ToastMonitor-GTK.git ~/repos/ToastMonitor-GTK
cd ~/repos/ToastMonitor-GTK
export PATH="$HOME/dev-tools/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin:$PATH"
swift build
swift test
swift run ToastMonitor
```

On **GNOME Shell 46**, the bundled **ToastMonitor extension** opens a native popup from the top bar, showing today's usage, costs, balances and quotas. The Debian package carries the extension's source; the app and login helper install it as a **user extension** in `~/.local/share/gnome-shell/extensions/`. Log out and back in after installation or migration from 1.0.4. First-login activation is automatic; later disabling is respected. See [installation and panel details](docs/gnome-extension.md). The extension uses the application's session-bus interface and hides the fallback tray while connected. The collector does not start automatically at login.

For the ordinary tray menu, install and enable [AppIndicator and KStatusNotifierItem Support](https://extensions.gnome.org/extension/615/appindicator-support/), e.g. `sudo apt-get install gnome-shell-extension-appindicator` on Ubuntu. This fallback uses **StatusNotifierItem and DBusMenu over the session bus**, works on Wayland, and re-registers after a shell/extension restart. Other desktops with StatusNotifier support also work. Some hosts display only the icon; the total remains in its tooltip and menu. The application window remains accessible without either extension.

The tray uses the bundled `toastmonitor-token-symbolic` SVG: a filled circle with a transparent five-point star cutout. GNOME controls its foreground color through the symbolic icon theme. The app publishes its icon directory via `IconThemePath`, so this also works when running directly from an extracted archive. The [freedesktop icon naming specification](https://specifications.freedesktop.org/icon-naming/latest/) does not define a standard token icon.

A running, unlocked Secret Service is needed to save account credentials. Local collection works without it. The app does not copy macOS Keychain items; reconnect accounts on Linux. Claude and Codex continue reading their existing CLI login files.

## Build and install

```sh
./scripts/build-app.sh                 # release binary and Linux resources → dist/linux/
./scripts/install-linux.sh             # installs under ~/.local; no root required
./scripts/install-linux.sh --autostart # also enables login startup
ToastMonitor --background             # start hidden in the tray
./scripts/package-release.sh          # Linux archive for the current architecture
./scripts/package-deb.sh              # Debian/Ubuntu package → dist/release/
./scripts/package-extension.sh        # optional GNOME Shell 46 extension ZIP
```

Building a `.deb` also requires `dpkg-dev` (for `dpkg-shlibdeps` and `dpkg-architecture`). The package bundles the Swift runtimes, declares system-library dependencies, and installs under `/usr`. Install it with `sudo apt install ./dist/release/toastmonitor_1.0.6-1_amd64.deb` (adjust the filename for your version and architecture). `TM_VERSION` and `TM_DEB_REVISION` set the package version; `TM_DEB_MAINTAINER` optionally sets its maintainer field. Installation does not enable login autostart.

GitHub Actions compiles, tests and packages the application on pushes to `main`, pull requests, and manual runs. Download the `.deb` and SHA-256 checksum from the run's `toastmonitor-linux-amd64-<commit>` artifact, retained for 30 days. CI uses the run number as the Debian revision; manual runs can set the package version. Both the debug application and the extracted release package undergo the isolated tray integration check. No package is installed or release published by this workflow.

For a staging install, set `DESTDIR` and `PREFIX` (default `$HOME/.local`). `SWIFT` can name a specific Swift executable. Launching the desktop entry again presents the existing window instead of starting another collector. Use **Quit** or Ctrl+Q to stop the app.

## Data and sources

Data: `$XDG_DATA_HOME/toastmonitor/toastmonitor.db` (default `~/.local/share/toastmonitor/toastmonitor.db`). Backups: the `backups/` subdirectory; private permissions (directories 0700, files 0600). Settings live in SQLite; secrets live only in Secret Service. `TM_DATABASE_PATH` provides an isolated database for tests.

| Tool | Local source |
|---|---|
| Claude Code | `~/.claude/projects/*/*.jsonl` |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl` and `state_5.sqlite` |
| OpenCode | `~/.local/share/opencode/opencode.db` |
| Hermes | `~/.hermes/state.db` and profile databases |
| Oh My Pi | `~/.omp/agent/sessions/**/*.jsonl` |
| DeepSeek Harness | `$DSH_HOME` (default `~/.dsh`) logs / projection cache |

DSH log mode uses `zstd`; fallback cache mode is sticky to prevent double counting. Codex cached tokens are already included in input and are not added twice. Recorded spend and estimated API value remain separate.

For macOS data migration, copy a protected database backup into the Linux data directory **before starting the app**. Do not copy a live WAL database without its WAL sidecar; use a SQLite backup instead. Never overwrite existing Linux usage without backing it up first.

## Command line

`ToastMonitor --help` lists supported options. Credential values are read from stdin:

```sh
ToastMonitor --provision-or-key
ToastMonitor --provision-go WORKSPACE_ID
ToastMonitor --provision-commandcode
ToastMonitor --provision-hermes https://your-host.example/usage.json
ToastMonitor --export-diagnostics /tmp/toastmonitor-diagnostics.json
```

Paste secrets when prompted by stdin, or pipe them from a secret manager. Do not put secrets in shell command history. DeepSeek Platform sessions are pasted in Preferences; the macOS browser-login automation is not used on Linux. Updates use Linux packaging/rebuilds, not the macOS updater. Native GNOME fonts, colors and light/dark preference follow the desktop.

## Verification

```sh
swift test
./scripts/smoke-linux.sh
```

The smoke check uses a private database, a session bus and Xvfb. It exercises the real application's tray properties, symbolic icon path, DBusMenu, single-instance activation, live refresh, window capture and quit action. Historical macOS UI and updater tests are excluded from the Linux target; the portable parser, quota, database, backup, restore and aggregation suites run on Linux.

The initial port was verified with Swift 6.0.3, GTK 4.14.5 and libadwaita 1.5.0: **263 tests passed**, debug and release builds succeeded, and the isolated tray integration check passed. The symbolic icon was also checked for a transparent star cutout and host-controlled light/dark recoloring. Staged installation and the release archive checksum were verified. Linux CI runs build, tests, tray smoke and release compilation on Ubuntu 24.04.

MIT license. See [LICENSE](LICENSE).
