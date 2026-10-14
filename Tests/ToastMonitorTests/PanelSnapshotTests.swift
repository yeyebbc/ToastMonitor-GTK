import XCTest

@testable import ToastMonitor

final class PanelSnapshotTests: XCTestCase {
    func testLoadingIsNotReportedAsZeroUsage() throws {
        let value = PanelSnapshot.usage(nil)
        XCTAssertFalse(value.ready)
        XCTAssertEqual(value.tokens, "—")
        let json = try XCTUnwrap(value.json())
        let decoded = try JSONDecoder().decode(PanelSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.version, 1)
        XCTAssertTrue(decoded.accounts.isEmpty)
    }

    func testSummaryPreservesCostSemanticsAndCodexCacheAccounting() throws {
        let totals = Database.ToolTotals(
            tool: "codex", input: 1_000, output: 100,
            cacheRead: 500, cacheWrite: 0, cost: 12.5, count: 4)
        let quality = UsageQueryService.CostQuality(estimated: 12.5, actual: 3.25)
        let snapshot = UsageQueryService.LightSnapshot(
            today: totals, week: totals, month: totals, all: totals,
            todayTokens: 1_100, weekTokens: 1_100, monthTokens: 1_100, allTokens: 1_100,
            byToolToday: [totals], byToolWeek: [totals], byToolMonth: [totals], byToolAll: [totals],
            costToday: quality, costWeek: quality, costMonth: quality, costAll: quality,
            apiValueToday: 12.5, apiValueWeek: 12.5, apiValueMonth: 12.5, apiValueAll: 12.5,
            subscriptions: [], lastScan: 100, fetchedAt: 200)
        let value = PanelSnapshot.usage(snapshot)
        XCTAssertTrue(value.ready)
        XCTAssertEqual(value.updatedAt, 200)
        XCTAssertEqual(value.apiValue, Format.money(12.5))
        XCTAssertEqual(value.recordedSpend, Format.money(3.25))
        XCTAssertEqual(value.sources.first?.value, Format.compact(1_100), "Codex cache is already in input")
        XCTAssertEqual(value.calls, "4")
        let json = try XCTUnwrap(value.json())
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertNil(keys["sessions"])
        XCTAssertNil(keys["credentials"])
    }

    func testQuotaKeepsStaleStatusAndBoundsProgress() {
        let stale = PanelSnapshot.Row.quota(
            "codex", "Codex", percent: 110, reset: 10,
            updated: 5, failed: true, now: 20)
        XCTAssertEqual(stale.fraction, 1)
        XCTAssertEqual(stale.value, "100% used")
        XCTAssertTrue(stale.detail.contains("last known quota"))
        XCTAssertTrue(stale.detail.contains("Reset pending refresh"))
        let invalid = PanelSnapshot.Row.quota(
            "codex", "Codex", percent: .nan, reset: nil,
            updated: 0, failed: false)
        XCTAssertNil(invalid.fraction)
        XCTAssertEqual(invalid.value, "—")
        XCTAssertEqual(PanelSnapshot.money(.infinity), "—")
    }
}
