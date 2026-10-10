import Adwaita
import Foundation

@MainActor
struct PreferencesView: View {
    var runtime: LinuxRuntime
    @State private var routerKey = ""
    @State private var goWorkspace = ""
    @State private var goCookie = ""
    @State private var commandCookie = ""
    @State private var deepSeekToken = ""
    @State private var platformToken = false
    @State private var feedURL = ""
    @State private var subscriptionName = ""
    @State private var subscriptionPrice = ""
    @State private var annualSubscription = false

    nonisolated var view: Body {
        MainActor.assumeIsolated { content }
    }

    @ViewBuilder var content: Body {
        VStack {
        PreferencesGroup().title("General").child {
            SwitchRow("Calendar Periods", isOn: .init {
                UsagePeriodSettings.shared.mode == .calendar
            } set: { value in
                UsagePeriodSettings.shared.setMode(value ? .calendar : .recent)
                runtime.refresh()
            }).subtitle("Use calendar weeks and months instead of rolling 7-day and 30-day windows.").useMarkup(false)
            SwitchRow("Start Weeks on Sunday", isOn: .init {
                UsagePeriodSettings.shared.weekStart == .sunday
            } set: { value in
                UsagePeriodSettings.shared.setWeekStart(value ? .sunday : .monday)
                runtime.refresh()
            })
            SwitchRow("Claude Subscription Quota", isOn: .init {
                ClaudeQuotaClient.shared.enabled
            } set: { ClaudeQuotaClient.shared.setEnabled($0) })
                .subtitle("Opt in to reading the existing Claude Code OAuth login on this computer.").useMarkup(false)
            SwitchRow("Codex Uses a Subscription", isOn: .init {
                Database.shared.codexBilledBySubscription()
            } set: { value in
                CodexBillingModeCoordinator.shared.set(value ? "subscription" : "api", restoreSelection: { _ in
                    runtime.message = "Could not save Codex billing mode."
                    runtime.revision += 1
                })
            }).subtitle("Exclude estimated Codex API costs from spend; retain its token totals and API value.").useMarkup(false)
            ActionRow().title("Background Collection").subtitle("Closing this window keeps the tray and collectors running. Use Quit to stop.").useMarkup(false)
            ActionRow().title("GNOME Tray Support").subtitle("GNOME Shell needs the AppIndicator and KStatusNotifierItem Support extension. The window works without it.").useMarkup(false)
        }
        PreferencesGroup().title("Sources").description("Local files are used by default. Remote sources require an explicitly configured feed.").child {
            EntryRow("Remote Feed URL", text: $feedURL)
            Button("Save Feed URL") {
                runtime.message = HermesRemoteClient.shared.provision(url: feedURL.isEmpty ? nil : feedURL)
                    ? "Remote feed saved" : "Invalid feed URL: use HTTPS or a private network address."
                if !runtime.message.hasPrefix("Invalid") { feedURL = "" }
            }.padding()
            ForEach(ToolKind.allCases.filter { $0 != .openrouter }) { tool in
                if tool.supportsRemoteSource {
                    SwitchRow("\(tool.displayName): Use Remote Feed", isOn: .init {
                        tool.sourceIsRemote
                    } set: { value in
                        if value && HermesRemoteClient.shared.feedURL.isEmpty {
                            runtime.message = "Save a remote feed URL before switching sources."
                        } else {
                            _ = tool.setSource(remote: value)
                            runtime.refreshNow()
                        }
                    })
                } else {
                    ActionRow().title(tool.displayName).subtitle("Local logs").useMarkup(false)
                }
            }
        }
        PreferencesGroup().title("OpenRouter").description("Secrets are stored in GNOME Keyring through Secret Service.").child {
            PasswordEntryRow("API Key", text: $routerKey)
            HStack {
                Button("Connect") {
                    runtime.message = OpenRouterClient.shared.provisionKey(routerKey) ? "OpenRouter connected" : "Could not save key. Check the key and unlock GNOME Keyring."
                    routerKey = ""
                }
                Button("Disconnect") {
                    runtime.message = OpenRouterClient.shared.setKey(nil) ? "OpenRouter disconnected" : "Could not remove key. Unlock GNOME Keyring."
                }
            }.padding()
        }
        PreferencesGroup().title("OpenCode Go").child {
            EntryRow("Workspace ID", text: $goWorkspace)
            PasswordEntryRow("Session Cookie", text: $goCookie)
            HStack {
                Button("Connect") {
                    runtime.message = OpenCodeGoClient.shared.provision(workspaceId: goWorkspace, cookie: goCookie) ? "OpenCode Go connected" : "Could not save credentials. Check the workspace ID and cookie."
                    goCookie = ""
                }
                Button("Disconnect") { OpenCodeGoClient.shared.clear(); runtime.message = "OpenCode Go credentials removal requested" }
            }.padding()
        }
        PreferencesGroup().title("Command Code").child {
            PasswordEntryRow("Studio Session Cookie", text: $commandCookie)
            HStack {
                Button("Connect") {
                    runtime.message = CommandCodeQuotaClient.shared.provision(cookie: commandCookie) ? "Command Code connected" : "Could not save cookie. Unlock GNOME Keyring and check the value."
                    commandCookie = ""
                }
                Button("Disconnect") { CommandCodeQuotaClient.shared.clear(); runtime.message = "Command Code credentials removal requested" }
            }.padding()
        }
        PreferencesGroup().title("DeepSeek").description("API keys provide balance only. Platform session tokens also provide account-wide spend.").child {
            SwitchRow("Use Platform Session Token", isOn: $platformToken)
            PasswordEntryRow(platformToken ? "Platform Session Token" : "API Key", text: $deepSeekToken)
            HStack {
                Button("Connect") {
                    DeepSeekBillingClient.shared.connect(deepSeekToken, kind: platformToken ? .platform : .apiKey)
                    deepSeekToken = ""
                    runtime.message = "Checking DeepSeek credentials…"
                }
                Button("Disconnect") { DeepSeekBillingClient.shared.disconnect() }
            }.padding()
            if let error = DeepSeekBillingClient.shared.connectionError {
                ActionRow().title("Connection Failed").subtitle(error).useMarkup(false)
            }
        }
        PreferencesGroup().title("Fixed Subscriptions").child {
            EntryRow("Subscription Name", text: $subscriptionName)
            EntryRow("Price per Cycle (USD)", text: $subscriptionPrice)
            SwitchRow("Annual Billing", isOn: $annualSubscription)
            Button("Add Subscription") {
                let name = subscriptionName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.count <= 256, let price = Double(subscriptionPrice),
                      price.isFinite, price >= 0, price < 1_000_000 else {
                    runtime.message = "Enter a subscription name and a valid non-negative price."
                    return
                }
                let saved = Database.shared.upsertSubscription(.init(id: 0, name: name, plan: "",
                    startDate: Int64(Date().timeIntervalSince1970), cycle: annualSubscription ? "yearly" : "monthly",
                    price: price, currency: "USD"))
                runtime.message = saved ? "Subscription added" : "Could not save subscription."
                if saved { subscriptionName = ""; subscriptionPrice = ""; runtime.refresh() }
            }.padding()
            if let snapshot = runtime.snapshot {
                ForEach(snapshot.subscriptions) { subscription in
                    ActionRow().title(subscription.name).useMarkup(false)
                        .subtitle("\(subscription.price) \(subscription.currency) · \(subscription.cycle)")
                        .suffix {
                            Button("Remove") {
                                runtime.message = Database.shared.deleteSubscription(id: subscription.id)
                                    ? "Subscription removed" : "Could not remove subscription."
                                runtime.refresh()
                            }.padding()
                        }
                }
            }
        }
        PreferencesGroup().title("Data").child {
            ActionRow().title("Database").subtitle(LinuxPaths.dataDirectory().appendingPathComponent("toastmonitor.db").path).useMarkup(false)
            Button("Create Protected Backup") {
                Task.detached(priority: .utility) {
                    let backup = DataMaintenance.createBackup()
                    await MainActor.run { runtime.message = backup.map { "Backup saved to \($0)" } ?? "Backup failed. Check the data directory permissions." }
                }
            }.padding()
            Button("Export Usage Database") {
                Task.detached(priority: .utility) {
                    let destination = LinuxPaths.dataDirectory().appendingPathComponent("exports", isDirectory: true)
                        .appendingPathComponent("usage-\(Int(Date().timeIntervalSince1970)).db").path
                    let saved = DataMaintenance.exportDatabase(to: destination)
                    await MainActor.run { runtime.message = saved ? "Export saved to \(destination)" : "Export failed. Check the data directory permissions." }
                }
            }.padding()
            ActionRow().title("Privacy").subtitle("Usage stays on this computer. Only explicitly connected accounts and remote feeds are contacted.").useMarkup(false)
            ActionRow().title("Updates").subtitle("Update through your package manager or rebuild this app. macOS app-bundle updates do not apply on Linux.").useMarkup(false)
        }
        }.spacing(24)
    }
}
