import XCTest
@testable import NX2Apple

final class TonTonCloudTransportTests: XCTestCase {
    func testOriginalContainerIsTheDefault() {
        XCTAssertTrue(GameboxCloud.usesOriginalBackups(overrides: [:], settings: [:]))
        XCTAssertEqual(TonTonCloudStatus.Transport(playerIsDefault: true, overrides: [:], envFiles: [:]), .original)
    }

    func testDisplayedTransportFollowsFolderAndPlayerOverrides() {
        let folder = ["DM_SAVE_SYNC": "/tmp/shared-saves"]
        XCTAssertEqual(TonTonCloudStatus.Transport(playerIsDefault: true, overrides: [:], envFiles: folder), .folder)
        XCTAssertEqual(TonTonCloudStatus.Transport(playerIsDefault: true, overrides: ["DM_SAVE_SYNC": "0"], envFiles: folder), .local)
        XCTAssertEqual(TonTonCloudStatus.Transport(playerIsDefault: false, overrides: folder, envFiles: [:]), .local)
        XCTAssertEqual(TonTonCloudStatus.Transport(playerIsDefault: true, overrides: ["DM_SAVE": "/tmp/separate-save"], envFiles: [:]), .local)
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
