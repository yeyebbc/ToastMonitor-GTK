import Adwaita
import CAdw
import Foundation

@MainActor
struct SettingsView: View {
    let runtime: LinuxRuntime
    nonisolated var view: Body { MainActor.assumeIsolated { content } }
    @ViewBuilder var content: Body {
        let selected = runtime.settingsPage
        VStack {
            ScrollView {
                HStack {
                    ForEach(SettingsPage.allCases, horizontal: true) { tab in
                        ToggleButton().child {
                            VStack {
                                NativeSymbol(name: tab.icon)
                                Text(tab.rawValue)
                            }.spacing(5).valign(.center)
                        }.active(.init(get: { selected == tab }, set: { if $0 { runtime.settingsPage = tab } }))
                            .style("flat")
                    }.spacing(8).inspectOnAppear { storage in
                        NativeToggleGroup.apply(storage.opaquePointer?.cast())
                        gtk_box_set_homogeneous(storage.opaquePointer?.cast(), 1)
                    }
                }.halign(.center).padding(12).style("tm-settings-tabs")
            }.horizontalNavigation()
            ScrollView {
                PreferencesView(runtime: runtime)
                    .frame(maxWidth: 800).padding(24)
            }.vexpand()
            RuntimeNotice(runtime: runtime)
        }.style("toastmonitor-window").css { NativeTypography.css }
        .topToolbar {
            HeaderBar.empty().headerBarTitle { Text(runtime.settingsPage.rawValue).style("heading") }
        }
    }
}

@MainActor
struct RuntimeNotice: View {
    let runtime: LinuxRuntime
    nonisolated var view: Body { MainActor.assumeIsolated { content } }
    @ViewBuilder var content: Body {
        if !runtime.message.isEmpty {
            Separator()
            HStack {
                Text(runtime.message).selectable().wrap().xalign(0).hexpand()
                Button("Dismiss") { runtime.message = "" }.valign(.center)
            }.spacing(12).padding(12)
        }
    }
}

enum LinuxAppearance {
    static var theme: String { Database.shared.setting("linux_theme") ?? "System" }
    static func apply() {
        let scheme = theme == "Dark" ? ADW_COLOR_SCHEME_FORCE_DARK : theme == "Light" ? ADW_COLOR_SCHEME_FORCE_LIGHT : ADW_COLOR_SCHEME_DEFAULT
        adw_style_manager_set_color_scheme(adw_style_manager_get_default(), scheme)
    }
}

enum LinuxAutostart {
    static var url: URL {
        let root = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config").path
        return URL(fileURLWithPath: root).appendingPathComponent("autostart/io.github.yeyebbc.ToastMonitor.desktop")
    }
    static var enabled: Bool { FileManager.default.fileExists(atPath: url.path) }
    static func set(_ enabled: Bool) throws {
        if enabled {
            // Desktop Exec's quoted form requires escaping these four characters.
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
            let quoted = executable.reduce("") { $0 + ("\\\"`$".contains($1) ? "\\" : "") + String($1) }
                .replacingOccurrences(of: "%", with: "%%")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "[Desktop Entry]\nType=Application\nName=ToastMonitor\nExec=\"\(quoted)\" --background\nX-GNOME-Autostart-enabled=true\n".write(to: url, atomically: true, encoding: .utf8)
        } else if enabled != self.enabled {
            try FileManager.default.removeItem(at: url)
        }
    }
}
