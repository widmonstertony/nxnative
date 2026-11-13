import XCTest
@testable import NX2Apple

final class TonTonCloudTransportTests: XCTestCase {
    func testOriginalContainerIsTheDefault() {
        XCTAssertTrue(GameboxCloud.usesOriginalBackups(overrides: [:], settings: [:]))
    }

    func testFolderTransportNeverAlsoWritesToTheOriginalContainer() {
        for value in ["icloud", "/tmp/shared-saves", "0"] {
            XCTAssertFalse(GameboxCloud.usesOriginalBackups(overrides: ["DM_SAVE_SYNC": value], settings: [:]))
            XCTAssertFalse(GameboxCloud.usesOriginalBackups(overrides: [:], settings: ["DM_SAVE_SYNC": value]))
        }
    }

    func testAnotherPlayerOrExplicitSaveRootNeverTouchesOriginalBackups() {
        for key in ["DM_SAVE", "DM_ROOT"] {
            XCTAssertFalse(GameboxCloud.usesOriginalBackups(overrides: [key: "/tmp/other-player"], settings: [:]))
            XCTAssertFalse(GameboxCloud.usesOriginalBackups(overrides: [:], settings: [key: "/tmp/other-player"]))
        }
    }
}
