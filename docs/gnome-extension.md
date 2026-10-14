# GNOME Shell panel

ToastMonitor includes an optional GNOME Shell 46 extension, `toastmonitor@yeyebbc.github.io`. Clicking its top-bar indicator opens a native Shell popup with today's tokens and calls, estimated API value, recorded spend, per-tool totals, connected account balances and subscription quotas. The panel follows the Shell theme. Long account lists scroll; Overview, Preferences and Plans remain reachable below the scroll area.

The Swift application remains responsible for collection, authentication, pricing and SQLite. The extension uses the session bus only; it does not read credentials or the usage database and makes no network requests. Failed provider refreshes retain their last known quota or balance and are labeled accordingly. API value, recorded spend, balances and subscription fees are never added together.

## Install

Starting with 1.0.4, the Debian package installs the extension under `/usr/share/gnome-shell/extensions/` and a first-login setup helper under `/usr/libexec/toastmonitor/`. **Log out and back in after installing.** GNOME discovers new system extensions when its session starts, and the helper then enables this panel automatically. No separate ZIP installation or manual enable command is needed. Quit and reopen ToastMonitor after upgrading the app.

The helper runs through `/etc/xdg/autostart/io.github.yeyebbc.ToastMonitor-panel-setup.desktop` in each user's GNOME session. It records successful setup in `$XDG_STATE_HOME/toastmonitor/gnome-panel-setup-v1` (normally `~/.local/state/toastmonitor/`). Subsequent logins leave the user's choice unchanged. Explicitly disabled extensions and the global extensions-off switch are respected. It does not start the collector, alter other extensions, modify users' settings as root, or restart Shell. Unsupported versions or failed activation are not recorded as success.

Versions 1.0.3 and earlier copy the extension files but do not arrange activation. For those versions, or to re-enable a panel you disabled, log out and back in, then run:

```sh
gnome-extensions enable toastmonitor@yeyebbc.github.io
```

Alternatively, install the separately packaged extension for your user:

```sh
gnome-extensions install --force ./dist/release/toastmonitor@yeyebbc.github.io.shell-extension.zip
# Log out and back in if this is a new extension or an update on Wayland.
gnome-extensions enable toastmonitor@yeyebbc.github.io
```

Build the ZIP with `./scripts/package-extension.sh`. Install a matching ToastMonitor application as well; older versions do not expose the panel interface. The application menu entry is used by **Start ToastMonitor** when the collector is stopped. Installing or enabling the extension does not start the collector at login. Only GNOME 46 is currently declared supported.

While the extension is connected, the application marks its ordinary StatusNotifierItem passive so AppIndicator does not show a duplicate. Disabling the extension restores the normal tray. If Shell disconnects, the app releases the lease automatically. Other desktops continue to use the existing StatusNotifierItem/DBusMenu integration.

```sh
gnome-extensions disable toastmonitor@yeyebbc.github.io
```

## Session-bus interface

- Bus: `io.github.yeyebbc.ToastMonitor`
- Object: `/io/github/yeyebbc/ToastMonitor/Panel`
- Interface: `io.github.yeyebbc.ToastMonitor.Panel`
- `Snapshot`: read-only JSON string, schema `version: 1`; `ready: false` means loading, not zero usage.
- `SnapshotChanged(s)` and standard `PropertiesChanged` notify subscribers. Only changed payloads are emitted.
- `Open(s)`: accepts `Overview`, `Analysis`, `Plans`, `Sessions` or `Preferences`; rejects unknown pages.
- `Refresh()`: requests a refresh through the existing collectors, with a five-second click cooldown and existing provider backoff.
- `SetPanelActive(b)`: obtains/releases the fallback-tray lease, tied to the caller's unique bus name.
- `SetExpanded(b)`: reports popup visibility to the existing foreground refresh policy; only the lease owner can change it.

Payloads contain display strings, timestamps, tool totals and bounded quota fractions. They exclude secrets, raw provider errors, session titles and project paths. Like the existing tray summary, they are visible to other processes belonging to the same desktop user.

## Verification

`swift test` includes accounting/serialization cases. `scripts/test-panel-setup.py` checks first-login behavior, opt-outs and failure handling. The normal Linux smoke test exercises the actual D-Bus interface, navigation, invalid page rejection, refresh, lease ownership, extension disable and connection-loss recovery against an isolated database and session bus. `scripts/smoke-gnome-extension.sh` starts a separate headless GNOME 46 compositor with the panel initially disabled, runs the first-login helper, verifies activation and preserved disabling, and exercises the popup. Its temporary test driver permits evaluation only in that private Shell, never in the user's desktop. CI repeats this test with the helper extracted from the Debian package.
