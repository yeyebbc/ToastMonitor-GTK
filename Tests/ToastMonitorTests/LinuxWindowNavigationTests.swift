import XCTest
@testable import ToastMonitor

final class LinuxWindowNavigationTests: XCTestCase {
    func testOpeningSettingsPreservesDashboardSelection() async {
        await MainActor.run {
            let runtime = LinuxRuntime()
            runtime.show(.analysis)
            runtime.show(.preferences)
            XCTAssertEqual(runtime.page, .analysis)
            runtime.showSettings(.accounts)
            XCTAssertEqual(runtime.page, .analysis)
            XCTAssertEqual(runtime.settingsPage, .accounts)
            runtime.show(.sessions)
            XCTAssertEqual(runtime.page, .sessions)
            XCTAssertEqual(runtime.settingsPage, .accounts)
        }
    }
}
