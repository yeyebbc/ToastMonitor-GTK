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
    @State private var feedURL = HermesRemoteClient.shared.feedURL
    @State private var subscriptionName = ""
    @State private var subscriptionPrice = ""
    @State private var annualSubscription = false
    @State private var restoreVisible = false
    @State private var restorePath = ""

    nonisolated var view: Body {
        MainActor.assumeIsolated { content }
    }

    @ViewBuilder var content: Body {
        VStack {
            if runtime.settingsPage == .general { general }
            else if runtime.settingsPage == .appearance { appearance }
            else if runtime.settingsPage == .sources { sources }
            else if runtime.settingsPage == .accounts { accounts }
            else { data }
        }.spacing(28)
        .alertDialog(visible: $restoreVisible, heading: "Restore this backup?",
                     body: "Current usage data and settings will be replaced. A protected backup of the current database is created first.")
        .response("Cancel", role: .close) { }
        .response("Restore", appearance: .destructive, role: .default) {
            let path = restorePath
            Task.detached(priority: .utility) {
                let receipt = DataMaintenance.restoreWithReceipt(backupPath: path)
                await MainActor.run {
                    runtime.message = receipt.map { "Backup restored. Previous data saved to \($0)" }
                        ?? "Restore failed. Check the backup and data directory permissions."
                    runtime.refresh()
                }
            }
        }
    }

    @ViewBuilder private var general: Body {
        VStack {
            PreferencesGroup().child {
                SwitchRow("Launch at login", isOn: .init(get: { LinuxAutostart.enabled }, set: { value in
                    do { try LinuxAutostart.set(value); runtime.revision += 1 }
                    catch { runtime.message = "Could not update login startup: \(error.localizedDescription)" }
                }))
                ActionRow().title("Background collection").subtitle("Closing either window keeps collection running. Use Quit to stop.").useMarkup(false)
                ActionRow().title("Close popup when clicking elsewhere").subtitle("The GNOME popup follows the desktop's menu behavior.").useMarkup(false)
            }
            PreferencesGroup().title("Date Range").child {
                SwitchRow("Calendar periods", isOn: .init(get: { UsagePeriodSettings.shared.mode == .calendar }, set: {
                    UsagePeriodSettings.shared.setMode($0 ? .calendar : .recent); runtime.refresh()
                })).subtitle("Use calendar weeks and months instead of the last 7 and 30 days.").useMarkup(false)
                SwitchRow("Start weeks on Sunday", isOn: .init(get: { UsagePeriodSettings.shared.weekStart == .sunday }, set: {
                    UsagePeriodSettings.shared.setWeekStart($0 ? .sunday : .monday); runtime.refresh()
                }))
            }
        }.spacing(28)
    }

    @ViewBuilder private var appearance: Body {
        VStack {
            PreferencesGroup().title("Appearance").child {
                ActionRow().title("Theme").suffix {
                    Menu(LinuxAppearance.theme) {
                        MenuButton("System") { setTheme("System") }
                        MenuButton("Light") { setTheme("Light") }
                        MenuButton("Dark") { setTheme("Dark") }
                    }.valign(.center)
                }
                ActionRow().title("Font").subtitle("Follows GNOME's font and text size settings.").useMarkup(false)
            }
            PreferencesGroup().title("Popover").child {
                SwitchRow("Show full token count", isOn: panelBinding("panel_full_tokens"))
                SwitchRow("Show remaining quota", isOn: panelBinding("panel_remaining_quota"))
                SwitchRow("Show sources", isOn: panelBinding("panel_show_sources", fallback: true))
                SwitchRow("Show quota and accounts", isOn: panelBinding("panel_show_accounts", fallback: true))
                SwitchRow("Show activity", isOn: panelBinding("panel_show_activity", fallback: true))
            }
        }.spacing(28)
    }

    @ViewBuilder private var sources: Body {
        VStack {
                VStack {
                    PreferencesGroup().title("Data Sources").description(
                        "Local files are used by default. Remote sources require an explicitly configured feed."
                    ).child {
                        NativePreferencesRows(rows: sourceRows)
                    }
                    PreferencesGroup().title("Remote Feed").child {
                        EntryRow("Feed URL", text: $feedURL)
                    }
                    Button("Save Feed URL") {
                        let remote = HermesRemoteClient.shared
                        guard remote.provision(url: feedURL) else {
                            runtime.message = "Could not save feed URL. Use HTTPS or a private network address and check database permissions."
                            return
                        }
                        // Keep the persisted URL visible: saving an empty draft
                        // removes the feed, so clearing it here made a second save
                        // silently disable a successfully configured connection.
                        feedURL = remote.feedURL
                        runtime.message = feedURL.isEmpty ? "Remote feed disabled" : "Remote feed saved"
                        if !feedURL.isEmpty {
                            remote.poll { runtime.refresh() }
                        }
                    }.halign(.start)
                }.spacing(12)
            PreferencesGroup().title("Collectors").child {
                ActionRow().title("Local usage logs").subtitle("Use Rescan Now to collect newly written local logs.").useMarkup(false)
                    .suffix { Button("Rescan Now") { runtime.refreshNow() }.valign(.center) }
            }
        }.spacing(28)
    }

    @ViewBuilder private var accounts: Body {
        VStack {
            PreferencesGroup().title("Accounts").description("Credentials are stored in GNOME Keyring.").child {
                ExpanderRow().title("Claude").suffix { Text(ClaudeQuotaClient.shared.enabled ? "Quota monitoring on" : "Off").style("tm-secondary") }.useMarkup(false).rows {
                    SwitchRow("Monitor subscription quota", isOn: .init(get: { ClaudeQuotaClient.shared.enabled }, set: {
                        ClaudeQuotaClient.shared.setEnabled($0); runtime.revision += 1
                    })).subtitle("Reads the existing Claude Code login on this computer.").useMarkup(false)
                }
                ExpanderRow().title("OpenCode Go").suffix { Text(OpenCodeGoClient.shared.configured ? "Connected" : "Not connected").style("tm-secondary") }.rows {
                    EntryRow("Workspace ID", text: $goWorkspace)
                    PasswordEntryRow("Session Cookie", text: $goCookie)
                    ActionRow().title("Connection").suffix {
                        Button("Connect") {
                            runtime.message = OpenCodeGoClient.shared.provision(workspaceId: goWorkspace, cookie: goCookie) ? "OpenCode Go connected" : "Could not save credentials. Check the workspace and cookie."
                            goCookie = ""; runtime.revision += 1
                        }.insensitive(goWorkspace.isEmpty || goCookie.isEmpty).valign(.center)
                        Button("Disconnect") { OpenCodeGoClient.shared.clear(); runtime.revision += 1 }.valign(.center)
                    }
                }
                ExpanderRow().title("Codex").suffix { Text(CodexQuotaClient.shared.state.primaryPct == nil ? "Sign in with the Codex CLI" : "Connected").style("tm-secondary") }.rows {
                    SwitchRow("Uses a subscription", isOn: .init(get: { Database.shared.codexBilledBySubscription() }, set: { value in
                        CodexBillingModeCoordinator.shared.set(value ? "subscription" : "api", restoreSelection: { _ in
                            runtime.message = "Could not save Codex billing mode."; runtime.revision += 1
                        })
                    })).subtitle("Keep API value separate from spend covered by a subscription.").useMarkup(false)
                }
                ExpanderRow().title("Command Code").suffix { Text(CommandCodeQuotaClient.shared.state.configured ? "Connected" : "Not connected").style("tm-secondary") }.rows {
                    PasswordEntryRow("Studio Session Cookie", text: $commandCookie)
                    ActionRow().title("Connection").suffix {
                        Button("Connect") {
                            runtime.message = CommandCodeQuotaClient.shared.provision(cookie: commandCookie) ? "Command Code connected" : "Could not save cookie. Unlock GNOME Keyring."
                            commandCookie = ""; runtime.revision += 1
                        }.insensitive(commandCookie.isEmpty).valign(.center)
                        Button("Disconnect") { CommandCodeQuotaClient.shared.clear(); runtime.revision += 1 }.valign(.center)
                    }
                }
                ExpanderRow().title("OpenRouter").suffix { Text(OpenRouterClient.shared.hasKey ? "Connected" : "Not connected").style("tm-secondary") }.rows {
                    PasswordEntryRow("API Key", text: $routerKey)
                    ActionRow().title("Connection").suffix {
                        Button("Connect") {
                            runtime.message = OpenRouterClient.shared.provisionKey(routerKey) ? "OpenRouter connected" : "Could not save key. Check the key and unlock GNOME Keyring."
                            routerKey = ""; runtime.revision += 1
                        }.insensitive(routerKey.isEmpty).valign(.center)
                        Button("Disconnect") {
                            runtime.message = OpenRouterClient.shared.setKey(nil) ? "OpenRouter disconnected" : "Could not remove key. Unlock GNOME Keyring."
                            runtime.revision += 1
                        }.valign(.center)
                    }
                }
                ExpanderRow().title("DeepSeek").suffix { Text(DeepSeekBillingClient.shared.state.kind == nil ? "Not connected" : "Connected").style("tm-secondary") }.rows {
                    SwitchRow("Use Platform Session Token", isOn: $platformToken)
                    PasswordEntryRow(platformToken ? "Platform Session Token" : "API Key", text: $deepSeekToken)
                    ActionRow().title("Connection").subtitle("API keys provide balance. Platform tokens also provide account spend.").useMarkup(false).suffix {
                        Button("Connect") {
                            DeepSeekBillingClient.shared.connect(deepSeekToken, kind: platformToken ? .platform : .apiKey)
                            deepSeekToken = ""; runtime.message = "Checking DeepSeek credentials…"
                        }.insensitive(deepSeekToken.isEmpty).valign(.center)
                        Button("Disconnect") { DeepSeekBillingClient.shared.disconnect(); runtime.revision += 1 }.valign(.center)
                    }
                    if let error = DeepSeekBillingClient.shared.connectionError {
                        ActionRow().title("Connection failed").subtitle(error).useMarkup(false)
                    }
                }
            }
            PreferencesGroup().title("Subscriptions").child {
                ExpanderRow().title("Add Subscription…").rows {
                    EntryRow("Subscription Name", text: $subscriptionName)
                    EntryRow("Price per Cycle (USD)", text: $subscriptionPrice)
                    SwitchRow("Annual Billing", isOn: $annualSubscription)
                    ActionRow().title("Fixed subscription").suffix {
                        Button("Add Subscription") { addSubscription() }.valign(.center)
                            .insensitive(subscriptionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || subscriptionPrice.isEmpty)
                    }
                }
                NativePreferencesRows(rows: subscriptionRows)
            }
        }.spacing(28)
    }

    @ViewBuilder private var data: Body {
        VStack {
            PreferencesGroup().title("Backup").child {
                ActionRow().title("Export database").suffix {
                    Button("Export…") { exportDatabase() }.valign(.center)
                }
                ActionRow().title("Create protected backup").suffix {
                    Button("Back Up Now") {
                        Task.detached(priority: .utility) {
                            let backup = DataMaintenance.createBackup()
                            await MainActor.run {
                                runtime.message = backup.map { "Backup saved to \($0)" } ?? "Backup failed. Check data directory permissions."
                                runtime.revision += 1
                            }
                        }
                    }.valign(.center)
                }
            }
            PreferencesGroup().title("Rebuild Claude Code and Codex").child {
                ActionRow().title("Rebuild local usage data").suffix {
                    Button("Preview") {
                        Task.detached {
                            let preview = DataMaintenance.preview()
                            await MainActor.run { runtime.message = "Rebuild preview: \(preview.turns) turns and \(preview.sessions) sessions. No data has been changed." }
                        }
                    }.valign(.center)
                }
            }
            PreferencesGroup().title("Automatic Backups").description("Up to seven protected backups are kept locally.").child {
                if DataMaintenance.availableBackups().isEmpty {
                    ActionRow().title("No backups yet").subtitle("Create a protected backup above to save your current data.").useMarkup(false)
                } else {
                    NativePreferencesRows(rows: DataMaintenance.availableBackups().map { url in
                        NativePreferencesRow(url.path, ActionRow().title(DataMaintenance.managedBackupLabel(for: url).capitalized)
                            .subtitle(backupDetail(url)).useMarkup(false).suffix {
                                Button("Restore…") { restorePath = url.path; restoreVisible = true }.valign(.center)
                            })
                    })
                }
            }
            PreferencesGroup().title("Local Data").child {
                ActionRow().title("Database").subtitle(LinuxPaths.dataDirectory().appendingPathComponent("toastmonitor.db").path).useMarkup(false)
                ActionRow().title("Privacy").subtitle("Usage stays on this computer. Only connected accounts and remote feeds are contacted.").useMarkup(false)
            }
        }.spacing(28)
    }

    private func backupDetail(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let date = values?.contentModificationDate.map { Format.dateTime(Int64($0.timeIntervalSince1970)) } ?? ""
        let size = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
        return "\(date) · \(size)"
    }
    private func exportDatabase() {
        Task.detached(priority: .utility) {
            let destination = LinuxPaths.dataDirectory().appendingPathComponent("exports", isDirectory: true)
                .appendingPathComponent("usage-\(Int(Date().timeIntervalSince1970)).db").path
            let saved = DataMaintenance.exportDatabase(to: destination)
            await MainActor.run { runtime.message = saved ? "Export saved to \(destination)" : "Export failed. Check data directory permissions." }
        }
    }
    private func addSubscription() {
        let name = subscriptionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 256, let price = Double(subscriptionPrice),
              price.isFinite, price >= 0, price < 1_000_000 else {
            runtime.message = "Enter a subscription name and a valid non-negative price."; return
        }
        let saved = Database.shared.upsertSubscription(.init(id: 0, name: name, plan: "", startDate: Int64(Date().timeIntervalSince1970),
                                                            cycle: annualSubscription ? "yearly" : "monthly", price: price, currency: "USD"))
        runtime.message = saved ? "Subscription added" : "Could not save subscription."
        if saved { subscriptionName = ""; subscriptionPrice = ""; runtime.refresh() }
    }

    private func setTheme(_ theme: String) {
        guard Database.shared.setSetting("linux_theme", theme) else { runtime.message = "Could not save appearance."; return }
        LinuxAppearance.apply(); runtime.revision += 1
    }
    private func panelBinding(_ key: String, fallback: Bool = false) -> Binding<Bool> {
        .init(get: { Database.shared.setting(key).map { $0 == "1" } ?? fallback }, set: { value in
            if !Database.shared.setSetting(key, value ? "1" : "0") { runtime.message = "Could not save popup appearance." }
            runtime.revision += 1
        })
    }

    private var sourceRows: [NativePreferencesRow] {
        var rows: [NativePreferencesRow] = []
        for tool in ToolKind.allCases where tool != .openrouter {
            let content: AnyView
            if tool.supportsRemoteSource {
                content = ActionRow().title(tool.displayName).useMarkup(false).suffix {
                    NativeSegments(labels: ["Local", "Remote"], selected: tool.sourceIsRemote ? 1 : 0) { choice in
                        let value = choice == 1
                        if value && HermesRemoteClient.shared.feedURL.isEmpty {
                            runtime.message = "Save a remote feed URL before switching sources."
                        } else if !tool.setSource(remote: value) {
                            runtime.message = "Could not save source. Check database permissions."
                        } else {
                            if value { HermesRemoteClient.shared.poll { runtime.refresh() } }
                            runtime.refreshNow()
                        }
                    }.valign(.center)
                }
            } else {
                content = ActionRow().title(tool.displayName).useMarkup(false).suffix { Text("Local only").style("tm-secondary") }
            }
            rows.append(.init(tool.rawValue, content))
        }
        return rows
    }

    private var subscriptionRows: [NativePreferencesRow] {
        var rows: [NativePreferencesRow] = []
        for subscription in runtime.snapshot?.subscriptions ?? [] {
            rows.append(
                .init(
                    "subscription-\(subscription.id)",
                    ActionRow().title(subscription.name).useMarkup(false).titleLines(2)
                        .subtitle("\(subscription.price) \(subscription.currency) · \(subscription.cycle)")
                        .suffix {
                            Button("Remove") {
                                runtime.message =
                                    Database.shared.deleteSubscription(id: subscription.id)
                                    ? "Subscription removed" : "Could not remove subscription."
                                runtime.refresh()
                            }.padding(12, [.leading])
                        }))
        }
        return rows
    }

}
