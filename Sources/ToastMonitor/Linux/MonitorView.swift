import Adwaita
import CAdw
import Foundation

@MainActor
struct MonitorView: View {
    var runtime: LinuxRuntime
    nonisolated var view: Body { MainActor.assumeIsolated { content } }

    @ViewBuilder var content: Body {
        VStack {
            ScrollView {
                VStack {
                    if runtime.page == .overview { overview }
                    else if runtime.page == .analysis { analysis }
                    else if runtime.page == .plans { plans }
                    else { sessionList }
                }.spacing(16).padding(20)
            }.vexpand()
            RuntimeNotice(runtime: runtime)
        }
        .style("toastmonitor-window").css { NativeTypography.css }
        .toast("Collection complete", signal: runtime.collectionComplete)
        .topToolbar {
            HeaderBar { } end: {
                Menu(icon: .default(icon: .openMenu)) {
                    MenuButton("Settings…") { runtime.show(.preferences) }
                    MenuButton("Hide Dashboard") { runtime.hide() }
                    MenuButton("Quit", window: false) { runtime.quit() }
                }
            }.headerBarTitle {
                HStack {
                    NativeSegments(labels: ["Overview", "Analysis", "Plans", "Sessions"],
                        selected: [MonitorPage.overview, .analysis, .plans, .sessions].firstIndex(of: runtime.page) ?? 0) {
                            runtime.show([.overview, .analysis, .plans, .sessions][$0])
                        }
                    Button(icon: .default(icon: .viewRefresh)) { runtime.refreshNow() }
                        .style("flat").tooltip("Refresh usage and accounts")
                }.spacing(6)
            }
        }
    }

    @ViewBuilder var overview: Body {
        VStack {
            HStack {
                periodPicker
                Text(runtime.snapshot == nil ? "Collecting…" : "Usage updated").xalign(1).hexpand().style("tm-secondary")
                    .tooltip(runtime.snapshot.map { "Usage updated \(Format.dateTime($0.fetchedAt))" } ?? "Collecting local usage")
            }.spacing(12)
            if let snapshot = runtime.snapshot {
                VStack {
                    DashboardStats(stats: [
                        .init("Tokens", Format.compact(selectedTokens(snapshot))),
                        .init("Calls", Format.compact(selectedTotals(snapshot).count)),
                        .init("Actual Spend", Format.money(selectedCost(snapshot).actual), "Provider-reported variable spend. Fixed subscriptions are separate."),
                        .init("API Value", Format.money(selectedValue(snapshot)), "Estimated at public model prices; not your bill.")
                    ])
                    HStack {
                        BreakdownCard(title: "Tools", entries: selectedRows(snapshot).map { total in
                            .init(id: ToolKind(rawValue: total.tool)?.displayName ?? total.tool,
                                  tokens: ToolKind(rawValue: total.tool)?.totalTokens(total) ?? total.input + total.output,
                                  color: DashboardColors.index(total.tool))
                        }.sorted { $0.tokens > $1.tokens })
                        BreakdownCard(title: "Models", entries: modelEntries)
                }.spacing(16).inspect { storage, _ in gtk_box_set_homogeneous(storage.opaquePointer?.cast(), 1) }
                ActivityCard(heatmap: runtime.heatmap)
                }.spacing(16)
            } else {
                Text("Collecting local usage…").padding(32)
            }
        }.spacing(16)
    }

    private var modelEntries: [BreakdownEntry] {
        Dictionary(grouping: runtime.models, by: \.model).map { model, rows in
            BreakdownEntry(id: model, tokens: rows.reduce(0) { sum, row in
                sum + (ToolKind(rawValue: row.tool)?.totalTokens(input: row.input, output: row.output, cacheRead: row.cacheRead) ?? row.input + row.output)
            }, color: modelColors[model] ?? 0)
        }.sorted { $0.tokens > $1.tokens }
    }

    private var modelColors: [String: Int32] {
        let names = Set(runtime.models.map(\.model) + runtime.modelDaily.map(\.name)).sorted()
        return Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, Int32($0.offset % 6)) })
    }

    private var periodPicker: AnyView {
        NativeSegments(labels: UsagePeriodSlot.allCases.map { UsagePeriodSettings.shared.configuration.label(for: $0) },
                       selected: UsagePeriodSlot.allCases.firstIndex(of: runtime.period) ?? 0) {
            runtime.period = UsagePeriodSlot.allCases[$0]; runtime.refresh()
        }
    }

    @ViewBuilder var analysis: Body {
        VStack {
            HStack {
                NativeSegments(labels: ["Tokens", "Cost"], selected: runtime.analysisCost ? 1 : 0) { runtime.analysisCost = $0 == 1 }
                Text("").hexpand()
                NativeSegments(labels: ["7 Days", "30 Days", "90 Days"], selected: [7, 30, 90].firstIndex(of: runtime.analysisDays) ?? 1) {
                    runtime.analysisDays = [7, 30, 90][$0]; runtime.refresh()
                }
                NativeSegments(labels: ["By Tool", "By Model"], selected: runtime.analysisByModel ? 1 : 0) { runtime.analysisByModel = $0 == 1 }
                Button(icon: .custom(name: "document-save-symbolic")) { exportDaily() }.style("flat")
                    .tooltip("Export daily usage as CSV").insensitive(runtime.daily.isEmpty)
            }.spacing(10)
            DashboardStats(stats: [
                .init("Tokens", Format.compact(analysisEntries.reduce(0) { $0 + $1.tokens })),
                .init("Estimated Cost", Format.money(analysisEntries.reduce(0) { $0 + $1.cost }), "API value at public model prices; not recorded spend."),
                .init("Daily Avg Tokens", Format.compact(analysisEntries.reduce(0) { $0 + $1.tokens } / Int64(runtime.analysisDays))),
                .init("Calls", Format.compact(analysisEntries.reduce(0) { $0 + $1.calls }))
            ])
            VStack {
                Text(runtime.analysisCost ? "Estimated Cost per Day" : "Tokens per Day").xalign(0).style("tm-heading")
                FlowBox(analysisEntries, selection: nil) { entry in
                    HStack {
                        NativeDot(color: entry.color)
                        Text(entry.id).ellipsize().style("tm-secondary")
                    }.spacing(6).tooltip(entry.id)
                }.minChildrenPerLine(1).maxChildrenPerLine(8).columnSpacing(16).rowSpacing(6)
                NativeChart(mode: runtime.analysisCost ? 3 : 0, values: chartValues, series: max(1, analysisEntries.count), colors: chartColors,
                            labels: chartLabels, height: 220,
                            summary: "\(runtime.analysisDays) days of \(runtime.analysisCost ? "estimated API cost" : "tokens"). See the Details table below.")
                if analysisEntries.isEmpty { Text("No usage in this date range").style("tm-secondary") }
            }.spacing(16).padding(18).cardSurface()
            VStack {
                Text("Details").xalign(0).style("tm-heading")
                analysisTableRow(runtime.analysisByModel ? "Model" : "Tool", "Tokens", "Calls", "Cost", "Share", header: true)
                ForEach(analysisEntries) { entry in
                    Separator()
                    analysisTableRow(entry.id, Format.compact(entry.tokens), Format.compact(entry.calls), Format.money(entry.cost),
                        String(format: "%.1f%%", share(entry) * 100), color: entry.color, fraction: share(entry))
                }.spacing(10)
            }.spacing(14).padding(18).cardSurface()
        }.spacing(16)
    }

    private func share(_ entry: BreakdownEntry) -> Double {
        Double(entry.tokens) / Double(max(1, analysisEntries.reduce(0) { $0 + $1.tokens }))
    }

    private var analysisRows: [AnalysisDay] {
        if runtime.analysisByModel { return runtime.modelDaily }
        return runtime.daily.map { day in
            .init(day: day.day, name: ToolKind(rawValue: day.tool)?.displayName ?? day.tool,
                  tokens: ToolKind(rawValue: day.tool)?.totalTokens(input: day.input, output: day.output, cacheRead: day.cacheRead) ?? day.input + day.output,
                  cost: day.cost, calls: day.count)
        }
    }
    private var analysisEntries: [BreakdownEntry] {
        Dictionary(grouping: analysisRows, by: \.name).map { name, rows in
            let tool = ToolKind.allCases.first { $0.displayName == name }
            return .init(id: name, tokens: rows.reduce(0) { $0 + $1.tokens }, calls: rows.reduce(0) { $0 + $1.calls },
                         cost: rows.reduce(0) { $0 + $1.cost },
                         color: runtime.analysisByModel ? modelColors[name] ?? 0 : tool.map { DashboardColors.index($0.rawValue) } ?? 0)
        }.sorted { $0.tokens > $1.tokens }
    }
    private var chartValues: [Double] {
        let grouped = Dictionary(grouping: analysisRows, by: \.day)
        let entries = analysisEntries
        return DashboardDate.dates(runtime.analysisDays).flatMap { date -> [Double] in
            let rows = grouped[DashboardDate.key(date)] ?? []
            if entries.isEmpty { return [0] }
            return entries.map { entry in rows.filter { $0.name == entry.id }.reduce(0.0) { $0 + (runtime.analysisCost ? $1.cost : Double($1.tokens)) } }
        }
    }
    private var chartColors: [Int32] {
        DashboardDate.dates(runtime.analysisDays).flatMap { _ in analysisEntries.isEmpty ? [0] : analysisEntries.map(\.color) }
    }
    private var chartLabels: [String] {
        let formatter = DateFormatter(); formatter.dateFormat = "MMM d"
        return DashboardDate.dates(runtime.analysisDays).map { formatter.string(from: $0) }
    }
    private func analysisTableRow(_ name: String, _ tokens: String, _ calls: String, _ cost: String, _ share: String,
                                  header: Bool = false, color: Int32? = nil, fraction: Double? = nil) -> AnyView {
        HStack {
            HStack {
                if let color { NativeDot(color: color) }
                else { Bin().frame(minWidth: 7) }
                Text(name).xalign(0).ellipsize().hexpand()
            }.spacing(8).hexpand()
            Text(tokens).xalign(1).frame(minWidth: 80)
            Text(calls).xalign(1).frame(minWidth: 65)
            Text(cost).xalign(1).frame(minWidth: 80)
            HStack {
                if let fraction {
                    ProgressBar().fraction(fraction).style("tm-share-\(color ?? 0)").frame(minWidth: 60).hexpand()
                }
                Text(share).xalign(1).frame(minWidth: 55).hexpand(header)
            }.spacing(8).frame(minWidth: 130)
        }.spacing(16).style(header ? "tm-table-heading" : "tm-value")
    }

    @ViewBuilder var plans: Body {
        let _ = runtime.revision
        FlowBox(planCards, selection: nil) { card in
            VStack {
                HStack {
                    Text(card.id).xalign(0).hexpand().style("tm-heading")
                    Button(icon: .custom(name: "view-refresh-symbolic")) { runtime.refreshNow() }.style("flat").tooltip("Refresh account")
                }.spacing(12)
                ForEach(card.rows) { row in
                    VStack {
                        HStack {
                            Text(row.title).xalign(0).wrap().hexpand().style("tm-secondary")
                            Text(row.value).selectable().style("tm-value")
                        }.spacing(12)
                        if let fraction = row.fraction { ProgressBar().fraction(fraction) }
                        Text(row.detail).xalign(0).wrap().style("tm-secondary")
                    }.spacing(6)
                }.spacing(14)
                if card.rows.isEmpty {
                    Text("Connect accounts to see balances and subscription quotas.").xalign(0).wrap().style("tm-secondary")
                    Button("Set Up…") { runtime.showSettings(.accounts) }.halign(.start)
                }
            }.spacing(16).padding(18).frame(minWidth: 270, minHeight: 150).cardSurface().valign(.start)
        }.minChildrenPerLine(1).maxChildrenPerLine(3).homogeneous(true).columnSpacing(12).rowSpacing(12)
    }
    private struct PlanCard: Identifiable { let id: String; let rows: [PanelSnapshot.Row] }
    private var planCards: [PlanCard] {
        var panel = PanelSnapshot(); panel.addAccounts()
        let groups = Dictionary(grouping: panel.accounts) { $0.title.components(separatedBy: " · ").first ?? $0.title }
        var result = groups.keys.sorted().map { PlanCard(id: $0, rows: groups[$0] ?? []) }
        for subscription in runtime.snapshot?.subscriptions ?? [] {
            result.append(.init(id: subscription.name, rows: [.init(id: "subscription-\(subscription.id)", title: subscription.plan,
                value: "\(subscription.price) \(subscription.currency)", detail: "Fixed subscription · \(subscription.cycle)")]))
        }
        result.append(.init(id: "Set Up Accounts", rows: []))
        return result
    }

    @ViewBuilder var sessionList: Body {
        VStack {
            HStack {
                Menu(runtime.sessionTool == "all" ? "All Tools" : ToolKind(rawValue: runtime.sessionTool)?.displayName ?? runtime.sessionTool) {
                    MenuButton("All Tools") { runtime.sessionTool = "all" }
                    ForEach(ToolKind.allCases) { tool in MenuButton(tool.displayName) { runtime.sessionTool = tool.rawValue } }
                }
                Text("\(filteredSessions.count) sessions").xalign(1).hexpand().style("tm-secondary")
                Button(icon: .custom(name: "view-refresh-symbolic")) { runtime.refresh() }.style("flat").tooltip("Refresh sessions")
            }.spacing(12)
            VStack {
                if filteredSessions.isEmpty {
                    Text("No sessions yet").style("tm-heading").padding(12)
                    Text("Collected sessions will appear here automatically.").style("tm-secondary").padding(12)
                } else {
                    ForEach(sessionGroups) { group in
                        VStack {
                            Text(group.title).xalign(0).style("tm-heading")
                            ForEach(group.sessions) { session in
                                HStack {
                                    NativeSymbol(name: "utilities-terminal-symbolic").style("tm-session-icon")
                                    VStack {
                                        Text(session.title ?? session.sessionID).xalign(0).ellipsize().style("tm-value")
                                        Text([session.project, session.model].compactMap { $0 }.joined(separator: " · ")).xalign(0).ellipsize().style("tm-secondary")
                                    }.spacing(4).hexpand()
                                    VStack {
                                        Text("\(Format.compact(ToolKind(rawValue: session.tool)?.totalTokens(input: session.input, output: session.output, cacheRead: session.cacheRead) ?? session.input + session.output)) tokens").xalign(1).style("tm-value")
                                        Text("\(Format.full(session.count)) calls · \(Format.money(session.cost)) API value").xalign(1).style("tm-secondary")
                                    }.spacing(4)
                                    Text(sessionTime(session.updated)).style("tm-secondary").frame(minWidth: 45)
                                }.spacing(14).padding(8, [.top, .bottom])
                                .tooltip("\(ToolKind(rawValue: session.tool)?.displayName ?? session.tool) · \(session.title ?? session.sessionID)")
                            }.spacing(4)
                        }.spacing(12)
                    }.spacing(22)
                }
            }.padding(18).cardSurface()
        }.spacing(16)
    }
    private var filteredSessions: [Database.SessionRow] {
        runtime.sessions.filter { runtime.sessionTool == "all" || $0.tool == runtime.sessionTool }
    }
    private struct SessionGroup: Identifiable { let id: Int64; let title: String; let sessions: [Database.SessionRow] }
    private var sessionGroups: [SessionGroup] {
        Dictionary(grouping: filteredSessions) { DashboardDate.key(Date(timeIntervalSince1970: Double($0.updated))) }
            .map { key, sessions in
                let date = Date(timeIntervalSince1970: Double(sessions[0].updated))
                let formatter = DateFormatter(); formatter.dateFormat = "EEE, MMM d"
                let title = Calendar.current.isDateInToday(date) ? "Today" : Calendar.current.isDateInYesterday(date) ? "Yesterday" : formatter.string(from: date)
                return SessionGroup(id: key, title: title, sessions: sessions)
            }.sorted { $0.id > $1.id }
    }
    private func sessionTime(_ timestamp: Int64) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
    }
    private func exportDaily() {
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
