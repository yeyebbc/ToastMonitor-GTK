// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToastMonitor",
    dependencies: [
        // Stable API compatible with Swift 6.0 and libadwaita 1.5.
        .package(url: "https://codeberg.org/aparoksha/adwaita-swift", exact: "0.1.0"),
        .package(url: "https://github.com/OpenCombine/OpenCombine", exact: "0.14.0"),
        .package(url: "https://github.com/apple/swift-crypto", exact: "3.12.3"),
    ],
    targets: [
        .systemLibrary(name: "SQLite3", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .systemLibrary(name: "CSecret", pkgConfig: "libsecret-1", providers: [.apt(["libsecret-1-dev"])]),
        .systemLibrary(name: "CGIO", pkgConfig: "gio-2.0", providers: [.apt(["libglib2.0-dev"])]),
        .target(name: "LinuxBridge", dependencies: ["CSecret", "CGIO", .product(name: "CAdw", package: "adwaita-swift")]),
        .executableTarget(
            name: "ToastMonitor",
            dependencies: ["SQLite3", "LinuxBridge", .product(name: "Adwaita", package: "adwaita-swift"),
                           .product(name: "OpenCombine", package: "OpenCombine"),
                           .product(name: "OpenCombineFoundation", package: "OpenCombine"),
                           .product(name: "OpenCombineDispatch", package: "OpenCombine"),
                           .product(name: "Crypto", package: "swift-crypto")],
            exclude: ["UI", "ToastMonitorApp.swift", "App/AppState.swift", "App/MenuBarFontSettings.swift",
                      "App/QuotaAlertManager.swift", "Core/UpdateChecker.swift", "Core/UpdateManager.swift",
                      "Collect/DeepSeekBrowserSession.swift", "Collect/KeychainStore.swift"],
            linkerSettings: [.linkedLibrary("util"), .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "$ORIGIN/../lib/toastmonitor"])]
        ),
        .testTarget(name: "ToastMonitorTests", dependencies: ["ToastMonitor", "SQLite3"],
                    exclude: ["DashboardWindowTests.swift", "DeepSeekBrowserSessionTests.swift",
                              "MenuBarFontTests.swift", "QuotaAlertTests.swift", "SettingsWindowTests.swift", "UIStateTests.swift",
                              "UpdateCheckerTests.swift"],
                    resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v5]
)
