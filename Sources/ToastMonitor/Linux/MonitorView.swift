import Adwaita
import Foundation

@MainActor
struct MonitorView: View {
    var runtime: LinuxRuntime

    nonisolated var view: Body {
        MainActor.assumeIsolated { content }
    }

    @ViewBuilder var content: Body {
        // The switcher compares previous bindings; snapshot the getter so external
        // navigation (tray, keyboard shortcuts) updates its selected tab too.
        let selectedPage = runtime.page
        VStack {
            ScrollView {
                ViewSwitcher(selection: Binding(get: { selectedPage }, set: { runtime.show($0) }))
                    .readableTitles()
                    .halign(.center)
                    .padding(12, [.top, .bottom])
                    .padding(24, [.leading, .trailing])
            }
            .horizontalNavigation()
            Separator()
            ScrollView {
                VStack {
                    VStack {
                        Text(runtime.page == .analysis ? "Daily Usage" : runtime.page.rawValue)
                            .wrap().xalign(0).style("tm-page-title")
                        if runtime.page == .analysis {
                            Text("Last 30 days · tokens, calls and estimated API value")
                                .wrap().xalign(0).style("tm-secondary")
                        }
                    }.spacing(6)
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
                }
                .spacing(24)
                .frame(maxWidth: 720)
                .padding(24)
            }
            .vexpand()
            if !runtime.message.isEmpty {
                Separator()
                HStack {
                    Text(runtime.message).selectable().wrap().xalign(0).hexpand()
                    Button("Dismiss") { runtime.message = "" }.valign(.center)
                }
                .spacing(12)
                .frame(maxWidth: 720)
                .padding(12, [.top, .bottom])
                .padding(24, [.leading, .trailing])
            }
        }
        .style("toastmonitor-window")
        .css { NativeTypography.css }
        .toast("Collection complete", signal: runtime.collectionComplete)
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
                periodPicker
                PreferencesGroup()
                    .title(UsagePeriodSettings.shared.configuration.title(for: runtime.period))
                    .child {
                        metric("Tokens", Format.full(selectedTokens(snapshot)))
                        metric("Model Calls", Format.full(selectedTotals(snapshot).count))
                        metric("API Value", Format.money(selectedValue(snapshot)), "Estimated at public model prices")
                        metric(
                            "Recorded Spend", Format.money(selectedCost(snapshot).actual),
                            "Provider-reported cost; subscription fees are separate")
                    }
                PreferencesGroup()
                    .title("Sources")
                    .description("Input, output and cached tokens; Codex input already includes its cache.")
                    .child {
                        let totals = selectedRows(snapshot)
                        NativePreferencesRows(
                            rows: totals.isEmpty
                                ? [
                                    NativePreferencesRow(
                                        "empty",
                                        ActionRow().title("No usage yet")
                                            .subtitle(
                                                "Use one of the supported tools. Local logs are collected automatically."
                                            )
                                            .useMarkup(false))
                                ]
                                : totals.map { total in
                                    NativePreferencesRow(
                                        total.id,
                                        metric(
                                            ToolKind(rawValue: total.tool)?.displayName ?? total.tool,
                                            Format.compact(
                                                ToolKind(rawValue: total.tool)?.totalTokens(total) ?? total.input),
                                            "\(Format.full(total.count)) calls · \(Format.money(total.cost)) API value")
                                    )
                                })
                    }
                if !runtime.models.isEmpty {
                    PreferencesGroup().title("Models").child {
                        List(Array(runtime.models.prefix(20)), selection: nil) { model in
                            metric(
                                model.model,
                                Format.compact(
                                    ToolKind(rawValue: model.tool)?.totalTokens(
                                        input: model.input, output: model.output, cacheRead: model.cacheRead)
                                        ?? (model.input + model.output)),
                                "\(ToolKind(rawValue: model.tool)?.displayName ?? model.tool) · \(Format.money(model.cost))"
                            )
                        }.boxedList()
                    }
                }
            }.spacing(24)
        } else {
            Text("Collecting local usage…").padding()
        }
    }

    @ViewBuilder var analysis: Body {
        VStack {
            if runtime.daily.isEmpty {
                NativePreferencesRows(rows: [
                    NativePreferencesRow(
                        "empty",
                        ActionRow().title("No daily history yet")
                            .subtitle("Daily totals will appear after usage is collected.").useMarkup(false))
                ])
            } else {
                ForEach(dailyGroups) { group in
                    PreferencesGroup().title(Format.dayKeyString(group.id)).child {
                        NativePreferencesRows(rows: group.rows.map(dailyRow))
                    }
                }.spacing(24)
            }
            Button("Export Daily CSV") {
                do {
                    let directory = LinuxPaths.dataDirectory().appendingPathComponent("exports", isDirectory: true)
                    try FileManager.default.createDirectory(
                        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let path = directory.appendingPathComponent("usage-\(Int(Date().timeIntervalSince1970)).csv")
                    let content =
                        "day,tool,input,output,cache_read,api_value_usd,calls\n"
                        + runtime.daily.map {
                            "\(Format.dayKeyString($0.day)),\($0.tool),\($0.input),\($0.output),\($0.cacheRead),\($0.cost),\($0.count)"
                        }.joined(separator: "\n") + "\n"
                    try content.write(to: path, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
                    runtime.message = "Exported to \(path.path)"
                } catch { runtime.message = "Export failed: \(error.localizedDescription)" }
            }.halign(.start).insensitive(runtime.daily.isEmpty)
        }.spacing(24)
    }

    private struct DailyGroup: Identifiable {
        let id: Int64
        let rows: [Database.DayAgg]
    }

    private func dailyRow(_ day: Database.DayAgg) -> NativePreferencesRow {
        let tool = ToolKind(rawValue: day.tool)
        let tokens = tool?.totalTokens(input: day.input, output: day.output, cacheRead: day.cacheRead) ?? day.input
        return NativePreferencesRow(
            day.id,
            metric(
                tool?.displayName ?? day.tool, Format.compact(tokens),
                "\(Format.full(day.count)) calls · \(Format.money(day.cost)) API value"
            ))
    }

    private var dailyGroups: [DailyGroup] {
        Dictionary(grouping: runtime.daily, by: \.day).map { day, rows in
            DailyGroup(id: day, rows: rows.sorted { $0.tool < $1.tool })
        }.sorted { $0.id > $1.id }
    }

    private var periodPicker: AnyView {
        HStack {
            Text("Usage period").xalign(0).style("tm-control-label").hexpand()
            Menu(UsagePeriodSettings.shared.configuration.label(for: runtime.period)) {
                MenuButton("Today") { selectPeriod(.today) }
                MenuButton("Week / 7 Days") { selectPeriod(.week) }
                MenuButton("Month / 30 Days") { selectPeriod(.month) }
                MenuButton("All Time") { selectPeriod(.all) }
            }.tooltip("Usage period")
        }.spacing(12)
    }

    private func selectPeriod(_ period: UsagePeriodSlot) {
        runtime.period = period
        runtime.refresh()
    }

    @ViewBuilder var plans: Body {
        // The lightweight refresh revision also refreshes these collector states.
        let _ = runtime.revision
        VStack {
            periodPicker
            planGroups
        }.spacing(24)
    }

    private var planGroups: Body {
        var groups: Body = []
        var rows: [NativePreferencesRow] = []
        let claude = ClaudeQuotaClient.shared.state
        if !ClaudeQuotaClient.shared.enabled {
            rows.append(
                .init(
                    "disabled",
                    metric(
                        "Quota monitoring is off", "",
                        "Enable it in Preferences to read your existing Claude Code login.")))
        }
        if let window = claude.fiveHour {
            rows.append(.init("five-hour", quota("5-hour Window", Double(window.usedPercent), window.resetAt)))
        }
        if let window = claude.sevenDay {
            rows.append(.init("weekly", quota("Weekly", Double(window.usedPercent), window.resetAt)))
        }
        if let window = claude.sevenDayOpus {
            rows.append(.init("opus", quota("Weekly Opus", Double(window.usedPercent), window.resetAt)))
        }
        if let error = claude.error { rows.append(.init("error", metric("Last refresh", "", error))) }
        groups.append(planGroup("Claude Subscription", rows))

        rows = []
        let codex = CodexQuotaClient.shared.state
        if let percent = codex.primaryPct {
            rows.append(.init("quota", quota(codex.planType ?? "Quota", Double(percent), codex.resetAt)))
        }
        if let error = codex.error { rows.append(.init("error", metric("Last refresh", "", error))) }
        if codex.primaryPct == nil && codex.error == nil {
            rows.append(.init("empty", metric("No quota available", "", "Sign in using the Codex CLI.")))
        }
        groups.append(planGroup("Codex Subscription", rows))

        rows = []
        let go = OpenCodeGoClient.shared.state
        if let value = go.rollingPct { rows.append(.init("rolling", quota("Rolling", value, go.rollingReset))) }
        if let value = go.weeklyPct { rows.append(.init("weekly", quota("Weekly", value, go.weeklyReset))) }
        if let value = go.monthlyPct { rows.append(.init("monthly", quota("Monthly", value, go.monthlyReset))) }
        if !OpenCodeGoClient.shared.configured {
            rows.append(
                .init("empty", metric("Not connected", "", "Add your workspace and session cookie in Preferences.")))
        }
        if let error = go.error { rows.append(.init("error", metric("Last refresh", "", error))) }
        groups.append(planGroup("OpenCode Go", rows))

        rows = []
        let router = OpenRouterClient.shared.state
        if let balance = router.accountBalance {
            rows.append(.init("balance", metric("Account Balance", Format.money(balance))))
        }
        if router.lastOK > 0 { rows.append(.init("spend", metric("Today's Spend", Format.money(router.usageDaily)))) }
        if !OpenRouterClient.shared.hasKey {
            rows.append(.init("empty", metric("Not connected", "", "Add an API key in Preferences.")))
        }
        if let error = router.error { rows.append(.init("error", metric("Last refresh", "", error))) }
        groups.append(planGroup("OpenRouter", rows))

        rows = []
        let command = CommandCodeQuotaClient.shared.state
        if let percent = command.monthlyUsedPercent {
            rows.append(
                .init(
                    "monthly",
                    quota(
                        command.planName ?? "Monthly", percent,
                        command.billingPeriodEnd.map { Int64($0.timeIntervalSince1970) })))
        }
        if let value = command.monthlyCreditsRemaining {
            rows.append(.init("credits", metric("Credits Remaining", Format.money(value))))
        }
        if !command.configured {
            rows.append(.init("empty", metric("Not connected", "", "Add a Studio cookie in Preferences.")))
        }
        if let error = command.error { rows.append(.init("error", metric("Last refresh", "", error))) }
        groups.append(planGroup("Command Code", rows))

        rows = []
        let deepSeek = DeepSeekBillingClient.shared.state
        if let balance = deepSeek.balance { rows.append(.init("balance", metric("Balance", balance.formatted))) }
        if let spend = deepSeek.spend {
            rows.append(
                .init("spend", metric("Period Spend", spend.amounts.map { $0.formatted }.joined(separator: " / "))))
        }
        if deepSeek.kind == nil {
            rows.append(
                .init(
                    "empty", metric("Not connected", "", "Connect an API key or Platform session token in Preferences.")
                ))
        }
        if let error = deepSeek.balanceError ?? deepSeek.spendError {
            rows.append(.init("error", metric("Last refresh", "", error)))
        }
        groups.append(planGroup("DeepSeek", rows))

        groups.append(
            planGroup(
                "Fixed Subscriptions",
                (runtime.snapshot?.subscriptions ?? []).map { subscription in
                    .init(
                        String(subscription.id),
                        metric(
                            subscription.name, "\(subscription.price) \(subscription.currency)",
                            "\(subscription.plan) · \(subscription.cycle)"))
                }))
        return groups
    }

    private func planGroup(_ title: String, _ rows: [NativePreferencesRow]) -> AnyView {
        PreferencesGroup().title(title).child { NativePreferencesRows(rows: rows) }
    }

    @ViewBuilder var sessionList: Body {
        PreferencesGroup().title("Recent Sessions").description("Newest first · up to 200 sessions · token totals").child {
            NativePreferencesRows(
                rows: runtime.sessions.isEmpty
                    ? [
                        NativePreferencesRow(
                            "empty",
                            ActionRow().title("No sessions yet")
                                .subtitle("Collected sessions will appear here automatically.").useMarkup(false))
                    ]
                    : runtime.sessions.map { session in
                        NativePreferencesRow(
                            session.id,
                            metric(
                                session.title ?? session.sessionID,
                                Format.compact(
                                    ToolKind(rawValue: session.tool)?.totalTokens(
                                        input: session.input, output: session.output, cacheRead: session.cacheRead)
                                        ?? session.input),
                                "\(ToolKind(rawValue: session.tool)?.displayName ?? session.tool) · \(session.updated > 0 ? Format.dateTime(session.updated) : "—") · \(Format.money(session.cost)) API value\n\(session.project ?? "No project")"
                            ))
                    })
        }
    }

    func metric(_ title: String, _ value: String, _ subtitle: String? = nil) -> AnyView {
        ActionRow().title(title).subtitle(subtitle).useMarkup(false).titleLines(2).subtitleLines(3)
            .suffix {
                if !value.isEmpty {
                    Text(value).selectable().xalign(1).style("tm-value").padding(12, [.leading])
                }
            }
            .tooltip([title, subtitle, value].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    func quota(_ title: String, _ percent: Double, _ reset: Int64?) -> AnyView {
        ActionRow().title(title).useMarkup(false).titleLines(2).subtitleLines(2)
            .subtitle(
                reset.map { "Resets \(Format.countdown($0 - Int64(Date().timeIntervalSince1970)))" }
                    ?? "Reset time unavailable"
            )
            .suffix {
                VStack {
                    Text("\(Int(percent.rounded()))% used").style("tm-value")
                    ProgressBar().fraction(min(max(percent / 100, 0), 1))
                }.spacing(6).frame(minWidth: 120).padding(12, [.leading])
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
