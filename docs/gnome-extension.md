# GNOME Shell panel

ToastMonitor includes an optional GNOME Shell 46 extension, `toastmonitor@yeyebbc.github.io`. Clicking its top-bar indicator opens a native Shell popup with today's tokens and calls, estimated API value, recorded spend, per-tool totals, connected account balances and subscription quotas. The panel follows the Shell theme. Long account lists scroll; Overview, Preferences and Plans remain reachable below the scroll area.

The Swift application remains responsible for collection, authentication, pricing and SQLite. The extension uses the session bus only; it does not read credentials or the usage database and makes no network requests. Failed provider refreshes retain their last known quota or balance and are labeled accordingly. API value, recorded spend, balances and subscription fees are never added together.

## Install

Starting with 1.0.5, the Debian package carries extension sources in `/usr/share/toastmonitor/gnome-extension/`, outside Shell's system extension directory. The application and login helper install them into the current user's `$XDG_DATA_HOME/gnome-shell/extensions/toastmonitor@yeyebbc.github.io` (normally `~/.local/share/gnome-shell/extensions/`). GNOME identifies this as a **user extension**, managed by that user. The package no longer installs a system extension.

**Log out and back in after installing or upgrading from 1.0.4.** During login, `/etc/xdg/autostart/io.github.yeyebbc.ToastMonitor-panel-install.desktop` runs the helper as the logged-in user in GNOME's Initialization phase, before Shell scans extension directories. `io.github.yeyebbc.ToastMonitor-panel-setup.desktop` enables the panel in the Applications phase after Shell starts. No separate ZIP installation or manual enable command is needed. Quit and reopen ToastMonitor after upgrading the app.

The helper lives in `/usr/libexec/toastmonitor/`. It records successful activation in `$XDG_STATE_HOME/toastmonitor/gnome-panel-setup-v1` (normally `~/.local/state/toastmonitor/`). Updates refresh user extension files even when that marker already exists; disabling the panel later is preserved. Explicitly disabled extensions and the global extensions-off switch are respected. It does not start the collector, alter other extensions, write user files as root, or restart Shell. Unsupported versions or failed activation are not recorded as success.

Upgrading from 1.0.4 removes the former `/usr/share/gnome-shell/extensions/toastmonitor@yeyebbc.github.io` package files. The running Shell may still report its previously loaded system copy until you log out; the next session loads the user copy.

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

`swift test` includes accounting/serialization cases. `scripts/test-panel-setup.py` checks user installation, file updates, first-login behavior, opt-outs and failure handling. `scripts/test-panel-login-order.py` runs an isolated real gnome-session with a test window-manager component to verify copying finishes before its WindowManager phase. The normal Linux smoke test exercises the actual D-Bus interface, navigation, invalid page rejection, refresh, lease ownership, extension disable and connection-loss recovery against an isolated database and session bus. `scripts/smoke-gnome-extension.sh` installs user files before starting an isolated headless GNOME 46 compositor, then runs activation after startup. It asserts GNOME reports type 2 (user extension) at the expected user path, verifies preserved disabling, and exercises the popup. It also starts a legacy app fixture with no panel interface to verify the connection timeout and subsequent recovery. Its temporary test driver permits evaluation only in that private Shell, never in the user's desktop. CI repeats this test using the helper, extension sources and app extracted from the Debian package; it does not run a full desktop login.

## Connection problems

If the panel reports that the running application has no panel interface, quit all ToastMonitor copies and start `/usr/bin/ToastMonitor`. A stale `~/.local/bin/ToastMonitor` launched by a user autostart entry can own the single-instance bus name and prevent a newer package from starting. Inspect `~/.config/autostart/` for old launchers and update their Exec entry to the installed application. The panel retries startup reads, shows a recovery instruction when the interface is absent, and reconnects when a compatible app starts.
