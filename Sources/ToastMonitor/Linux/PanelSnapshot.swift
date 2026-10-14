import Foundation

/// Versioned, presentation-only D-Bus payload. Never includes credentials,
/// session titles, project paths, or raw provider responses.
struct PanelSnapshot: Codable {
    struct Row: Codable, Identifiable {
        let id: String
        let title: String
        let value: String
        let detail: String
        var fraction: Double? = nil

        static func quota(
            _ id: String, _ title: String, percent: Double, reset: Int64?, updated: Int64,
            failed: Bool, now: Int64 = Int64(Date().timeIntervalSince1970)
        ) -> Row {
            guard percent.isFinite else {
                return Row(id: id, title: title, value: "—", detail: "Quota unavailable · open Plans")
            }
            let bounded = min(max(percent, 0), 100)
            let resetText =
                reset.map { $0 > now ? "Resets in \(Format.countdown($0 - now))" : "Reset pending refresh" }
                ?? "Reset time unavailable"
            let freshness =
                failed
                ? "Refresh failed · last known quota"
                : updated > 0 ? "Updated \(Format.dateTime(updated))" : "Not yet refreshed"
            return Row(
                id: id, title: title, value: "\(Int(bounded.rounded()))% used",
                detail: "\(resetText) · \(freshness)", fraction: bounded / 100)
        }
    }

    var version = 1
    var ready = false
    var updatedAt: Int64 = 0
    var tokens = "—"
    var tokenDetail = ""
    var calls = "—"
    var apiValue = "—"
    var recordedSpend = "—"
    var sources: [Row] = []
    var accounts: [Row] = []

    static func usage(_ snapshot: UsageQueryService.LightSnapshot?) -> PanelSnapshot {
        guard let snapshot else { return PanelSnapshot() }
        var result = PanelSnapshot()
        result.ready = true
        result.updatedAt = snapshot.fetchedAt
        result.tokens = Format.compact(snapshot.todayTokens)
        result.tokenDetail = Format.full(snapshot.todayTokens)
        result.calls = Format.full(snapshot.today.count)
        result.apiValue = money(snapshot.apiValueToday)
        result.recordedSpend = money(snapshot.costToday.actual)
        result.sources = snapshot.byToolToday.sorted { $0.tool < $1.tool }.map { total in
            let tool = ToolKind(rawValue: total.tool)
            let tokens = tool?.totalTokens(total) ?? total.input + total.output
            return Row(
                id: total.tool, title: tool?.displayName ?? total.tool, value: Format.compact(tokens),
                detail: "\(Format.full(total.count)) calls · \(money(total.cost)) API value")
        }
        return result
    }

    struct Period: Codable {
        let id: String
        let title: String
        let tokens: String
        let tokenDetail: String
        let calls: String
        let apiValue: String
        let recordedSpend: String
        let sources: [Row]
    }
    struct Activity: Codable {
        let day: Int64
        let tokens: Int64
        let month: String
    }
    var periods: [Period] = []
    var activity: [Activity] = []
    var activeDays = 0
    var showSources = true
    var showAccounts = true
    var showActivity = true
    var remainingQuota = false

    struct PresentationOptions {
        var fullTokens = false
        var remainingQuota = false
        var showSources = true
        var showAccounts = true
        var showActivity = true
        static func load() -> Self {
            .init(fullTokens: Database.shared.setting("panel_full_tokens") == "1",
                  remainingQuota: Database.shared.setting("panel_remaining_quota") == "1",
                  showSources: Database.shared.setting("panel_show_sources") != "0",
                  showAccounts: Database.shared.setting("panel_show_accounts") != "0",
                  showActivity: Database.shared.setting("panel_show_activity") != "0")
        }
    }

    @MainActor
    mutating func addPresentation(snapshot: UsageQueryService.LightSnapshot?, heatmap: [Int64: Int64],
                                  configuration: UsagePeriodConfiguration? = nil, options: PresentationOptions? = nil) {
        guard let snapshot else { return }
        let settings = options ?? PresentationOptions.load()
        let full = settings.fullTokens
        func format(_ n: Int64) -> String { full ? Format.full(n) : Format.compact(n) }
        let configuration = configuration ?? UsagePeriodSettings.shared.configuration
        let rows: [(UsagePeriodSlot, Int64, Int64, Double, Double, [Database.ToolTotals])] = [
            (.today, snapshot.todayTokens, snapshot.today.count, snapshot.apiValueToday, snapshot.costToday.actual, snapshot.byToolToday),
            (.week, snapshot.weekTokens, snapshot.week.count, snapshot.apiValueWeek, snapshot.costWeek.actual, snapshot.byToolWeek),
            (.month, snapshot.monthTokens, snapshot.month.count, snapshot.apiValueMonth, snapshot.costMonth.actual, snapshot.byToolMonth),
            (.all, snapshot.allTokens, snapshot.all.count, snapshot.apiValueAll, snapshot.costAll.actual, snapshot.byToolAll)
        ]
        periods = rows.map { slot, tokens, calls, value, spend, totals in
            Period(id: slot.rawValue, title: configuration.label(for: slot), tokens: format(tokens), tokenDetail: Format.full(tokens),
                   calls: Format.full(calls), apiValue: Self.money(value), recordedSpend: Self.money(spend),
                   sources: totals.sorted { (ToolKind(rawValue: $0.tool)?.totalTokens($0) ?? 0) > (ToolKind(rawValue: $1.tool)?.totalTokens($1) ?? 0) }.map { total in
                let tool = ToolKind(rawValue: total.tool)
                let n = tool?.totalTokens(total) ?? total.input + total.output
                return Row(id: total.tool, title: tool?.displayName ?? total.tool, value: format(n),
                           detail: String(format: "%.1f%%", Double(n) / Double(max(1, tokens)) * 100),
                           fraction: Double(n) / Double(max(1, tokens)))
            })
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -175 - weekday, to: today)!
        let formatter = DateFormatter(); formatter.dateFormat = "MMM"
        var previous = -1
        activity = (0..<(176 + weekday)).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: start) else { return nil }
            let key = DashboardDate.key(date)
            let month = calendar.component(.month, from: date)
            let name = index % 7 == 0 && month != previous ? formatter.string(from: date) : ""
            if !name.isEmpty { previous = month }
            return Activity(day: key, tokens: heatmap[key] ?? 0, month: name)
        }
        activeDays = heatmap.values.filter { $0 > 0 }.count
        showSources = settings.showSources
        showAccounts = settings.showAccounts
        showActivity = settings.showActivity
        remainingQuota = settings.remainingQuota
    }

    static func money(_ value: Double) -> String { value.isFinite ? Format.money(value) : "—" }

    func json() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @MainActor
    mutating func addAccounts() {
        let claude = ClaudeQuotaClient.shared.state
        if ClaudeQuotaClient.shared.enabled {
            for (id, title, window) in [
                ("claude-5h", "Claude · 5 hours", claude.fiveHour),
                ("claude-week", "Claude · Weekly", claude.sevenDay),
                ("claude-opus", "Claude · Weekly Opus", claude.sevenDayOpus),
            ] {
                if let window {
                    accounts.append(
                        .quota(
                            id, title, percent: Double(window.usedPercent), reset: window.resetAt,
                            updated: claude.lastSync, failed: claude.error != nil))
                }
            }
            if claude.fiveHour == nil && claude.sevenDay == nil && claude.sevenDayOpus == nil {
                accounts.append(
                    Row(id: "claude", title: "Claude", value: "—", detail: "Quota unavailable · open Plans"))
            }
        }
        let codex = CodexQuotaClient.shared.state
        if let percent = codex.primaryPct {
            accounts.append(
                .quota(
                    "codex", "Codex · \(codex.planType ?? "Quota")", percent: Double(percent),
                    reset: codex.resetAt, updated: codex.lastSync, failed: codex.error != nil))
        } else if codex.error != nil {
            accounts.append(Row(id: "codex", title: "Codex", value: "—", detail: "Quota unavailable · open Plans"))
        }
        let go = OpenCodeGoClient.shared.state
        if OpenCodeGoClient.shared.configured {
            for (id, title, percent, reset) in [
                ("go-rolling", "OpenCode Go · Rolling", go.rollingPct, go.rollingReset),
                ("go-week", "OpenCode Go · Weekly", go.weeklyPct, go.weeklyReset),
                ("go-month", "OpenCode Go · Monthly", go.monthlyPct, go.monthlyReset),
            ] {
                if let percent {
                    accounts.append(
                        .quota(
                            id, title, percent: percent, reset: reset,
                            updated: go.lastOK, failed: go.error != nil))
                }
            }
            if go.rollingPct == nil && go.weeklyPct == nil && go.monthlyPct == nil {
                accounts.append(
                    Row(id: "go", title: "OpenCode Go", value: "—", detail: "Quota unavailable · open Plans"))
            }
        }
        let router = OpenRouterClient.shared.state
        if OpenRouterClient.shared.hasKey {
            let detail =
                router.error != nil
                ? "Refresh failed · last known balance" : "Updated \(Format.dateTime(router.lastOK))"
            accounts.append(
                Row(
                    id: "router", title: "OpenRouter · Balance", value: router.accountBalance.map(Self.money) ?? "—",
                    detail: router.lastOK > 0 ? detail : "Waiting for account data"))
        }
        let command = CommandCodeQuotaClient.shared.state
        if command.configured {
            if let percent = command.monthlyUsedPercent {
                accounts.append(
                    .quota(
                        "command", "Command Code · Monthly", percent: percent,
                        reset: command.billingPeriodEnd.map { Int64($0.timeIntervalSince1970) },
                        updated: command.lastSync, failed: command.error != nil))
            } else {
                accounts.append(
                    Row(id: "command", title: "Command Code", value: "—", detail: "Quota unavailable · open Plans"))
            }
        }
        let deepSeek = DeepSeekBillingClient.shared.state
        if deepSeek.kind != nil {
            let detail =
                deepSeek.balanceError != nil
                ? "Refresh failed · last known balance"
                : deepSeek.balanceUpdated.map {
                    "Updated \(Format.dateTime(Int64($0.timeIntervalSince1970)))"
                } ?? "Waiting for account data"
            accounts.append(
                Row(
                    id: "deepseek", title: "DeepSeek · Balance", value: deepSeek.balance?.formatted ?? "—",
                    detail: detail))
        }
    }
}
