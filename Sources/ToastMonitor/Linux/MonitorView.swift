import Adwaita
import Foundation

@MainActor
struct MonitorView: View {
    var runtime: LinuxRuntime

    nonisolated var view: Body {
        MainActor.assumeIsolated { content }
    }

    @ViewBuilder var content: Body {
        VStack {
            HStack {
                Menu(runtime.page.rawValue) {
                    MenuButton("Overview") { runtime.show(.overview) }
                    MenuButton("Analysis") { runtime.show(.analysis) }
                    MenuButton("Plans") { runtime.show(.plans) }
                    MenuButton("Sessions") { runtime.show(.sessions) }
                    MenuButton("Preferences") { runtime.show(.preferences) }
                }
                    .hexpand()
                Menu(UsagePeriodSettings.shared.configuration.label(for: runtime.period)) {
                    MenuButton("Today") { runtime.period = .today; runtime.refresh() }
                    MenuButton("Week / 7 Days") { runtime.period = .week; runtime.refresh() }
                    MenuButton("Month / 30 Days") { runtime.period = .month; runtime.refresh() }
                    MenuButton("All Time") { runtime.period = .all; runtime.refresh() }
                }
            }
            .padding()
            ScrollView {
                VStack {
                    if runtime.page == .overview {
                        overview
                    } else if runtime.page == .analysis {
                        analysis
                    } else if runtime.page == .plans {
                        plans
                    } else if runtime.page == .sessions {
                        sessionList
                    } else {
                        PreferencesView(runtime: runtime)
                    }
                    if !runtime.message.isEmpty {
                        Text(runtime.message).wrap().halign(.start).padding()
                    }
                }
                .spacing(24)
                .padding()

            }
            .vexpand()
        }
        .topToolbar {
            HeaderBar {
                Button("Refresh") { runtime.refreshNow() }
            } end: {
                Menu(icon: .default(icon: .openMenu)) {
                    MenuButton("Preferences") { runtime.show(.preferences) }
                    MenuButton("Hide Window") { runtime.hide() }
                    MenuButton("Quit", window: false) { runtime.quit() }
                }
            }
            .headerBarTitle { WindowTitle(subtitle: runtime.page.rawValue, title: "ToastMonitor") }
        }
    }

    @ViewBuilder var overview: Body {
        if let snapshot = runtime.snapshot {
            VStack {
            PreferencesGroup()
                .title(UsagePeriodSettings.shared.configuration.title(for: runtime.period))
                .child {
                    metric("Tokens", Format.full(selectedTokens(snapshot)))
                    metric("Model Calls", Format.full(selectedTotals(snapshot).count))
                    metric("API Value", Format.money(selectedValue(snapshot)), "Estimated at public model prices")
                    metric("Recorded Spend", Format.money(selectedCost(snapshot).actual), "Provider-reported cost; subscription fees are separate")
                }
            PreferencesGroup()
                .title("Sources")
                .description("Input, output and cached tokens; Codex input already includes its cache.")
                .child {
                    ForEach(selectedRows(snapshot)) { total in
                        metric(ToolKind(rawValue: total.tool)?.displayName ?? total.tool,
                               Format.compact(ToolKind(rawValue: total.tool)?.totalTokens(total) ?? total.input),
                               "\(Format.full(total.count)) calls · \(Format.money(total.cost)) API value")
                    }
                    if selectedRows(snapshot).isEmpty {
                        ActionRow().title("No usage yet").subtitle("Use one of the supported tools. Local logs are collected automatically.").useMarkup(false)
                    }
                }
            if !runtime.models.isEmpty {
            PreferencesGroup().title("Models").child {
                ForEach(Array(runtime.models.prefix(20))) { model in
                    metric(model.model, Format.compact(ToolKind(rawValue: model.tool)?.totalTokens(input: model.input, output: model.output, cacheRead: model.cacheRead) ?? (model.input + model.output)),
                           "\(ToolKind(rawValue: model.tool)?.displayName ?? model.tool) · \(Format.money(model.cost))")
                }
            }
            }
            }.spacing(24)
        } else {
            Text("Collecting local usage…").padding()
        }
    }

    @ViewBuilder var analysis: Body {
        PreferencesGroup().title("Daily Usage · Last 30 Days").child {
            ForEach(runtime.daily.sorted { $0.day > $1.day }) { day in
                metric(Format.dayKeyString(day.day), Format.compact(ToolKind(rawValue: day.tool)?.totalTokens(input: day.input, output: day.output, cacheRead: day.cacheRead) ?? day.input),
                       "\(ToolKind(rawValue: day.tool)?.displayName ?? day.tool) · \(Format.full(day.count)) calls · \(Format.money(day.cost))")
            }
            if runtime.daily.isEmpty {
                ActionRow().title("No daily history yet").subtitle("Daily totals will appear after usage is collected.").useMarkup(false)
            }
        }
        Button("Export Daily CSV") {
            do {
                let directory = LinuxPaths.dataDirectory().appendingPathComponent("exports", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let path = directory.appendingPathComponent("usage-\(Int(Date().timeIntervalSince1970)).csv")
                let content = "day,tool,input,output,cache_read,api_value_usd,calls\n" + runtime.daily.map {
                    "\(Format.dayKeyString($0.day)),\($0.tool),\($0.input),\($0.output),\($0.cacheRead),\($0.cost),\($0.count)"
                }.joined(separator: "\n") + "\n"
                try content.write(to: path, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
                runtime.message = "Exported to \(path.path)"
            } catch { runtime.message = "Export failed: \(error.localizedDescription)" }
        }.padding()
    }

    @ViewBuilder var plans: Body {
        VStack {
        // The lightweight refresh revision also refreshes these collector states.
        let _ = runtime.revision
        PreferencesGroup().title("Claude Subscription").child {
            let state = ClaudeQuotaClient.shared.state
            if !ClaudeQuotaClient.shared.enabled {
                metric("Quota monitoring is off", "", "Enable it in Preferences to read your existing Claude Code login.")
            }
            if let window = state.fiveHour { quota("5-hour Window", Double(window.usedPercent), window.resetAt) }
            if let window = state.sevenDay { quota("Weekly", Double(window.usedPercent), window.resetAt) }
            if let window = state.sevenDayOpus { quota("Weekly Opus", Double(window.usedPercent), window.resetAt) }
            if let error = state.error { metric("Last refresh", "", error) }
        }
        PreferencesGroup().title("Codex Subscription").child {
            let state = CodexQuotaClient.shared.state
            if let percent = state.primaryPct { quota(state.planType ?? "Quota", Double(percent), state.resetAt) }
            if let error = state.error { metric("Last refresh", "", error) }
            if state.primaryPct == nil && state.error == nil { metric("No quota available", "", "Sign in using the Codex CLI.") }
        }
        PreferencesGroup().title("OpenCode Go").child {
            let state = OpenCodeGoClient.shared.state
            if let value = state.rollingPct { quota("Rolling", value, state.rollingReset) }
            if let value = state.weeklyPct { quota("Weekly", value, state.weeklyReset) }
            if let value = state.monthlyPct { quota("Monthly", value, state.monthlyReset) }
            if !OpenCodeGoClient.shared.configured { metric("Not connected", "", "Add your workspace and session cookie in Preferences.") }
            if let error = state.error { metric("Last refresh", "", error) }
        }
        PreferencesGroup().title("OpenRouter").child {
            let state = OpenRouterClient.shared.state
            if let balance = state.accountBalance { metric("Account Balance", Format.money(balance)) }
            metric("Today's Spend", Format.money(state.usageDaily))
            if !OpenRouterClient.shared.hasKey { metric("Not connected", "", "Add an API key in Preferences.") }
            if let error = state.error { metric("Last refresh", "", error) }
        }
        PreferencesGroup().title("Command Code").child {
            let state = CommandCodeQuotaClient.shared.state
            if let percent = state.monthlyUsedPercent { quota(state.planName ?? "Monthly", percent, state.billingPeriodEnd.map { Int64($0.timeIntervalSince1970) }) }
            if let value = state.monthlyCreditsRemaining { metric("Credits Remaining", Format.money(value)) }
            if !state.configured { metric("Not connected", "", "Add a Studio cookie in Preferences.") }
            if let error = state.error { metric("Last refresh", "", error) }
        }
        PreferencesGroup().title("DeepSeek").child {
            let state = DeepSeekBillingClient.shared.state
            if let balance = state.balance {
                metric("Balance", balance.formatted)
            }
            if let spend = state.spend { metric("Period Spend", spend.amounts.map { $0.formatted }.joined(separator: " / ")) }
            if state.kind == nil { metric("Not connected", "", "Connect an API key or Platform session token in Preferences.") }
            if let error = state.balanceError ?? state.spendError { metric("Last refresh", "", error) }
        }
        if let snapshot = runtime.snapshot {
            PreferencesGroup().title("Fixed Subscriptions").child {
                ForEach(snapshot.subscriptions) { subscription in
                    metric(subscription.name, "\(subscription.price) \(subscription.currency)", "\(subscription.plan) · \(subscription.cycle)")
                }
            }
        }
        }.spacing(24)
    }

    @ViewBuilder var sessionList: Body {
        PreferencesGroup().title("Recent Sessions").description("Newest first · up to 200 sessions").child {
            ForEach(runtime.sessions) { session in
                metric(session.title ?? session.sessionID, Format.compact(ToolKind(rawValue: session.tool)?.totalTokens(input: session.input, output: session.output, cacheRead: session.cacheRead) ?? session.input),
                       "\(ToolKind(rawValue: session.tool)?.displayName ?? session.tool) · \(session.project ?? "No project") · \(Format.dateTime(session.updated)) · \(Format.money(session.cost))")
            }
            if runtime.sessions.isEmpty {
                ActionRow().title("No sessions yet").subtitle("Collected sessions will appear here automatically.").useMarkup(false)
            }
        }
    }

    func metric(_ title: String, _ value: String, _ subtitle: String? = nil) -> AnyView {
        ActionRow().title(title).subtitle(subtitle).useMarkup(false).titleLines(1).subtitleLines(2)
            .suffix { Text(value).padding() }
    }

    func quota(_ title: String, _ percent: Double, _ reset: Int64?) -> AnyView {
        ActionRow().title(title).useMarkup(false)
            .subtitle(reset.map { "Resets \(Format.countdown($0 - Int64(Date().timeIntervalSince1970)))" } ?? "Reset time unavailable")
            .suffix {
                VStack {
                    Text("\(Int(percent.rounded()))% used")
                    ProgressBar().fraction(min(max(percent / 100, 0), 1))
                }.frame(minWidth: 130).padding()
            }
    }

    func selectedRows(_ snapshot: UsageQueryService.LightSnapshot) -> [Database.ToolTotals] {
        switch runtime.period {
        case .today: return snapshot.byToolToday
        case .week: return snapshot.byToolWeek
        case .month: return snapshot.byToolMonth
        case .all: return snapshot.byToolAll
        }
    }
    func selectedTokens(_ snapshot: UsageQueryService.LightSnapshot) -> Int64 {
        switch runtime.period {
        case .today: return snapshot.todayTokens
        case .week: return snapshot.weekTokens
        case .month: return snapshot.monthTokens
        case .all: return snapshot.allTokens
        }
    }
    func selectedTotals(_ snapshot: UsageQueryService.LightSnapshot) -> Database.ToolTotals {
        switch runtime.period {
        case .today: return snapshot.today
        case .week: return snapshot.week
        case .month: return snapshot.month
        case .all: return snapshot.all
        }
    }
    func selectedValue(_ snapshot: UsageQueryService.LightSnapshot) -> Double {
        switch runtime.period {
        case .today: return snapshot.apiValueToday
        case .week: return snapshot.apiValueWeek
        case .month: return snapshot.apiValueMonth
        case .all: return snapshot.apiValueAll
        }
    }
    func selectedCost(_ snapshot: UsageQueryService.LightSnapshot) -> UsageQueryService.CostQuality {
        switch runtime.period {
        case .today: return snapshot.costToday
        case .week: return snapshot.costWeek
        case .month: return snapshot.costMonth
        case .all: return snapshot.costAll
        }
    }
}

extension Database.ToolTotals: Identifiable { var id: String { tool } }
extension Database.DayAgg: Identifiable { var id: String { "\(day):\(tool)" } }
