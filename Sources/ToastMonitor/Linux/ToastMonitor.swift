import Adwaita
import Foundation
import Glibc

@main
struct ToastMonitor: App {
    var app: AdwaitaApp

    static func main() {
        if DebugLog.enabled { NSLog("[ToastMonitor] setting up application") }
        let program = setupApp()
        if DebugLog.enabled { NSLog("[ToastMonitor] running application") }
        program.app.run {
            if DebugLog.enabled { NSLog("[ToastMonitor] application activated") }
            // A second desktop launch activates the existing window.
            if program.app.storage.sceneStorage.isEmpty {
                for element in program.scene { element.setupInitialContainers(app: program.app) }
                Idle { MainActor.assumeIsolated { LinuxRuntime.shared.start(app: program.app) } }
            } else {
                program.app.showWindow("main")
            }
        }
    }

    init() {
        if LinuxCLI.run(Array(CommandLine.arguments.dropFirst())) { exit(0) }
        if DebugLog.enabled { NSLog("[ToastMonitor] creating Adwaita application") }
        app = AdwaitaApp(id: "io.github.yeyebbc.ToastMonitor")
        if DebugLog.enabled { NSLog("[ToastMonitor] application created") }
    }

    var scene: Scene {
        Window(id: "main") { _ in
            MainActor.assumeIsolated { MonitorView(runtime: .shared) }
        }
        .title("ToastMonitor")
        .defaultSize(width: 720, height: 760)
        .closeShortcut()
        .appKeyboardShortcut("q".ctrl()) { _ in MainActor.assumeIsolated { LinuxRuntime.shared.quit() } }
        .appKeyboardShortcut("comma".ctrl()) { _ in MainActor.assumeIsolated { LinuxRuntime.shared.show(.preferences) } }
    }
}

enum LinuxCLI {
    static func run(_ arguments: [String]) -> Bool {
        guard let command = arguments.first else { return false }
        switch command {
        case "--help", "-h":
            print("""
            ToastMonitor — GNOME AI usage monitor
              --background                 Start with the window hidden
              --show-dashboard             Open the dashboard (default)
              --help, --version
              --provision-or-key           Read an OpenRouter key from stdin
              --provision-go WORKSPACE     Read an OpenCode Go cookie from stdin
              --provision-commandcode      Read a Command Code cookie from stdin
              --provision-hermes URL       Configure the remote usage feed
              --clear-or-key, --clear-go
              --export-diagnostics PATH    Export redacted diagnostics
            Credentials are stored in GNOME Secret Service, never in argv.
            """)
        case "--version": print("ToastMonitor GNOME 1.0.6")
        case "--provision-or-key", "--set-or-key":
            Database.shared.open()
            guard let secret = readLine(), !secret.isEmpty,
                  OpenRouterClient.shared.provisionKey(secret) else { fail("Could not save key; unlock GNOME Keyring and check the key.") }
        case "--provision-go":
            Database.shared.open()
            guard arguments.count == 2, let secret = readLine(),
                  OpenCodeGoClient.shared.provision(workspaceId: arguments[1], cookie: secret) else { fail("Could not save OpenCode Go credentials.") }
        case "--provision-commandcode":
            Database.shared.open()
            MainActor.assumeIsolated {
                guard let secret = readLine(), CommandCodeQuotaClient.shared.provision(cookie: secret) else { fail("Could not save Command Code credentials.") }
            }
        case "--provision-hermes":
            Database.shared.open()
            guard arguments.count == 2, HermesRemoteClient.shared.provision(url: arguments[1]) else { fail("Invalid remote feed URL.") }
        case "--clear-or-key":
            guard KeychainStore.delete(account: "or-keys") else { fail("Could not remove key.") }
        case "--clear-go":
            guard KeychainStore.delete(account: "go-auth-cookie"), KeychainStore.delete(account: "go-workspace-id") else { fail("Could not remove credentials.") }
        case "--export-diagnostics":
            guard arguments.count == 2 else { fail("A destination path is required.") }
            Database.shared.open()
            do {
                let data = try JSONSerialization.data(withJSONObject: Database.shared.diagnosticsSummary(), options: [.prettyPrinted, .sortedKeys])
                let url = URL(fileURLWithPath: arguments[1])
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch { fail(error.localizedDescription) }
        case "--background", "--show-dashboard": return false
        default: fail("Unknown option: \(command). Use --help.")
        }
        return true
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
