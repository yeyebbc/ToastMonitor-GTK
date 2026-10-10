# Contributing

ToastMonitor targets Linux/GNOME using adwaita-swift. Follow the dependencies and Swift setup in [README.md](README.md).

Run `swift build`, `swift test` and `./scripts/smoke-linux.sh` before submitting a change. Parser and database changes must preserve event identity, incremental scan cursors, transactions, protected backups and provider cost semantics. Keep credentials in Secret Service and never log secrets.

UI changes should use libadwaita controls and respect GNOME light/dark settings. Verify at a narrow window width and with no tray extension. Closing the window must preserve background collection; Quit must stop the application.

Dependency versions are pinned in Package.swift and Package.resolved. Do not switch adwaita-swift to main without updating the required Swift and libadwaita versions.
