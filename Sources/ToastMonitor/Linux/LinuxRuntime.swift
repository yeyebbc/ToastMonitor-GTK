import Adwaita
import Foundation
import LinuxBridge

enum MonitorPage: String, CaseIterable, Identifiable, CustomStringConvertible, ViewSwitcherOption {
    case overview = "Overview"
    case analysis = "Analysis"
    case plans = "Plans"
    case sessions = "Sessions"
    case preferences = "Preferences"
    var id: Self { self }
    var description: String { rawValue }
    var title: String { rawValue }
    var icon: Icon {
        switch self {
        case .overview: return .default(icon: .viewGrid)
        case .analysis: return .default(icon: .viewList)
        case .plans: return .default(icon: .accessoriesCalculator)
        case .sessions: return .default(icon: .documentOpenRecent)
        case .preferences: return .default(icon: .preferencesSystem)
        }
    }
    init?(title: String) { self.init(rawValue: title) }
}

@MainActor
final class LinuxRuntime {
    static let shared = LinuxRuntime()
    @State(forceUpdates: true) var page: MonitorPage = .overview
    @State(forceUpdates: true) var period: UsagePeriodSlot = .today
    @State(forceUpdates: true) var snapshot: UsageQueryService.LightSnapshot? = nil
    @State(forceUpdates: true) var models: [Database.ModelAgg] = []
    @State(forceUpdates: true) var sessions: [Database.SessionRow] = []
    @State(forceUpdates: true) var daily: [Database.DayAgg] = []
    @State(forceUpdates: true) var message = ""
    @State(forceUpdates: true) var revision = 0
    private var app: AdwaitaApp?
    private var window: UnsafeMutableRawPointer?
    private var lastRefresh = Date.distantPast
    private var inFlight = false
    private var visible = false
    private var started = false
    private var extraPeriod: UsagePeriodSlot = .today
    private var captured = false
    private var startTime = Date()
    private var panelExpanded = false
    private var lastPanelPublish = Date.distantPast
    private var lastExplicitRefresh = Date.distantPast
    private var panelSetupProcess: Process?

    func start(app: AdwaitaApp) {
        if DebugLog.enabled { NSLog("[ToastMonitor] runtime starting") }
        guard !started else { return }
        started = true
        self.app = app
        if ProcessInfo.processInfo.environment["TM_TEST_MODE"] != "1" {
            installUserPanel()
        }
        startTime = Date()
        Database.shared.open()
        window = tm_main_window()
        if let pageName = ProcessInfo.processInfo.environment["TM_PREVIEW_PAGE"],
           let previewPage = MonitorPage(rawValue: pageName) { page = previewPage }
        if let window { tm_window_keep_alive(window) }
        tm_app_hold()
        if tm_tray_start({ action in MainActor.assumeIsolated { LinuxRuntime.shared.handle(action) } }, {
            MainActor.assumeIsolated { LinuxRuntime.shared.tick() }
        }) == 0 { message = "Tray unavailable. You can continue using this window." }
        if CommandLine.arguments.contains("--background"), let window { tm_window_hide(window) }
        if ProcessInfo.processInfo.environment["TM_TEST_MODE"] != "1" {
            CollectorEngine.shared.start()
            OpenRouterClient.shared.start()
            OpenCodeGoClient.shared.start()
            ClaudeQuotaClient.shared.start()
            CodexQuotaClient.shared.start()
            CommandCodeQuotaClient.shared.start()
            DeepSeekBillingClient.shared.start()
            HermesRemoteClient.shared.start()
        }
        refresh()
    }

    private func installUserPanel() {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let helper = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("libexec/toastmonitor/enable-gnome-panel")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return }
        let process = Process()
        process.executableURL = helper
        do {
            try process.run()
            panelSetupProcess = process
        } catch {
            NSLog("[ToastMonitor] Could not install the user panel: %@", error.localizedDescription)
        }
    }

    func tick() {
        // Integrate Foundation timers and Swift's main dispatch queue with GLib.
        _ = RunLoop.main.run(mode: .default, before: Date())
        if !captured, Date().timeIntervalSince(startTime) > 3,
           let path = ProcessInfo.processInfo.environment["TM_SCREENSHOT_PATH"], let window {
            captured = tm_window_capture(window, path) != 0
        }
        let currentVisibility = window.map { tm_window_visible($0) != 0 } ?? false
        if currentVisibility != visible {
            visible = currentVisibility
            // Foreground observers can start quota requests even when start()
            // skipped the collectors. Keep isolated previews fully offline.
            if ProcessInfo.processInfo.environment["TM_TEST_MODE"] != "1" {
                NotificationCenter.default.post(name: TMNotifications.dashboardVisibility, object: visible)
            }
            if visible { lastRefresh = .distantPast }
        }
        if Date().timeIntervalSince(lastPanelPublish) >= 1 { publishPanel() }
        if Date().timeIntervalSince(lastRefresh) >= TMRefreshPolicy.snapshotInterval(foreground: visible || panelExpanded) { refresh() }
    }

    private func publishPanel() {
        lastPanelPublish = Date()
        var panel = PanelSnapshot.usage(snapshot)
        panel.addAccounts()
        if let json = panel.json() { tm_panel_update(json) }
    }

    private func setPanelExpanded(_ expanded: Bool) {
        guard panelExpanded != expanded else { return }
        panelExpanded = expanded
        if ProcessInfo.processInfo.environment["TM_TEST_MODE"] != "1" {
            NotificationCenter.default.post(name: TMNotifications.popoverVisibility, object: expanded)
        }
        if expanded { lastRefresh = .distantPast }
    }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        lastRefresh = Date()
        UsageQueryService.shared.loadLightSnapshot(configuration: UsagePeriodSettings.shared.configuration) { [weak self] snap in
            guard let self else { return }
            self.snapshot = snap
            self.inFlight = false
            self.revision += 1
            self.publishPanel()
            tm_tray_update(Format.compact(snap.todayTokens), "Today: \(Format.full(snap.todayTokens)) tokens · \(Format.money(snap.apiValueToday)) API value")
        }
        if visible {
            // Queries stay on the service's worker queue.
            UsageQueryService.shared.loadSnapshot(configuration: UsagePeriodSettings.shared.configuration) { [weak self] full in
                guard let self else { return }
                switch self.period {
                case .today: self.models = full.modelAggsToday
                case .week: self.models = full.modelAggs
                case .month: self.models = full.modelAggsMonth
                case .all: self.models = full.modelAggsAll
                }
            }
            UsageQueryService.shared.loadSessions(tool: nil, limit: 200) { [weak self] in self?.sessions = $0 }
            UsageQueryService.shared.loadDailyAggs(days: 30) { [weak self] in self?.daily = $0 }
            if extraPeriod != period {
                extraPeriod = period
                DeepSeekBillingClient.shared.select(period, configuration: UsagePeriodSettings.shared.configuration)
            }
        }
    }

    func refreshNow() {
        guard Date().timeIntervalSince(lastExplicitRefresh) >= 5 else { return }
        lastExplicitRefresh = Date()
        if ProcessInfo.processInfo.environment["TM_TEST_MODE"] == "1" { refresh(); return }
        CollectorEngine.shared.scheduleScan(force: true) { [weak self] receipt in
            self?.message = receipt.failedSources.isEmpty ? "Collection complete" : "Retrying: " + receipt.failedSources.joined(separator: ", ")
            self?.refresh()
        }
        OpenRouterClient.shared.refresh()
        OpenCodeGoClient.shared.refresh()
        ClaudeQuotaClient.shared.refresh(force: true)
        CodexQuotaClient.shared.refresh()
        CommandCodeQuotaClient.shared.refresh()
        DeepSeekBillingClient.shared.refresh(force: true)
    }

    func show(_ page: MonitorPage) {
        self.page = page
        if let window { tm_window_present(window) }
        lastRefresh = .distantPast
    }

    func hide() { if let window { tm_window_hide(window) } }
    func quit() {
        tm_tray_stop()
        tm_app_release()
        app?.quit()
    }
    private func handle(_ action: Int32) {
        switch action {
        case 0: show(.overview)
        case 1: show(.sessions)
        case 2: show(.preferences)
        case 3: refreshNow()
        case 4: quit()
        case 5: show(.analysis)
        case 6: show(.plans)
        case 7: setPanelExpanded(true)
        case 8: setPanelExpanded(false)
        default: break
        }
    }
}
