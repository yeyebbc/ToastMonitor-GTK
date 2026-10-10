import Foundation
import LinuxBridge

enum TMNotifications {
    static let popoverVisibility = Notification.Name("tmPopoverVisibility")
    static let dashboardVisibility = Notification.Name("tmDashboardVisibility")
    static let usagePeriodSettingsChanged = Notification.Name("tmUsagePeriodSettingsChanged")
}

enum TMRefreshPolicy {
    static func quotaInterval(foreground: Bool) -> TimeInterval { foreground ? 60 : 300 }
    static func snapshotInterval(foreground: Bool) -> TimeInterval { foreground ? 2 : 5 }
}

func autoreleasepool<T>(_ body: () throws -> T) rethrows -> T { try body() }

enum LinuxPaths {
    static func dataDirectory(environment: [String: String] = ProcessInfo.processInfo.environment,
                              home: String = NSHomeDirectory()) -> URL {
        let configured = environment["XDG_DATA_HOME"] ?? ""
        let base = configured.hasPrefix("/") ? configured : home + "/.local/share"
        return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent("toastmonitor", isDirectory: true)
    }
}

/// Existing collectors keep their credential API; storage is GNOME Secret Service.
enum KeychainStore {
    static var lastWasInteractionNotAllowed: Bool { tm_secret_failed() != 0 }
    static func get(account: String, allowPrompt: Bool = false) -> String? {
        guard let raw = tm_secret_get(account) else { return nil }
        defer { tm_secret_free(raw) }
        return String(cString: raw)
    }
    static func set(_ value: String, account: String, allowPrompt: Bool = false) -> Bool {
        tm_secret_set(account, value) != 0
    }
    @discardableResult static func delete(account: String, allowPrompt: Bool = false) -> Bool {
        tm_secret_delete(account) != 0
    }
}
