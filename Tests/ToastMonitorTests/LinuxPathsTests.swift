import XCTest
@testable import ToastMonitor

final class LinuxPathsTests: XCTestCase {
    func testXDGDataHomeOverridesDefaultDirectory() {
        XCTAssertEqual(LinuxPaths.dataDirectory(environment: ["XDG_DATA_HOME": "/data/private"], home: "/home/test").path,
                       "/data/private/toastmonitor")
    }

    func testUnsetEmptyAndRelativeXDGPathsUseHome() {
        for environment in [[:], ["XDG_DATA_HOME": ""], ["XDG_DATA_HOME": "relative/path"]] {
            XCTAssertEqual(LinuxPaths.dataDirectory(environment: environment, home: "/home/test").path,
                           "/home/test/.local/share/toastmonitor")
        }
    }

    func testManagedBackupsStayUnderApplicationData() {
        XCTAssertEqual(DataMaintenance.directory, LinuxPaths.dataDirectory().appendingPathComponent("backups", isDirectory: true))
    }
}
