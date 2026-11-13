import XCTest
@testable import NXCore

final class GameBuildSetupTests: XCTestCase {
    func testUnboundCatalogEntryOpensFileSetup() {
        XCTAssertEqual(GameBuildSetup.action(inputs: [:], running: false), .chooseFiles)
        XCTAssertEqual(GameBuildSetup.chooseFiles.buttonKey, "launch.chooseBuildFiles")
    }

    func testFoldersAndNUPsCountWithoutAnNSPBaseSlot() {
        for source in ["/games/dump", "/games/game.nup"] {
            XCTAssertEqual(GameBuildSetup.action(inputs: ["folder": [source]], running: false), .configure)
        }
        XCTAssertEqual(GameBuildSetup.action(inputs: ["base": ["/games/base.nsp"]], running: false), .configure)
    }

    func testOnlyUpdatesOrEmptySlotsStillNeedAFullSource() {
        for inputs in [["folder": [""]], ["base": []], ["update": ["/games/update.nsp"]]] {
            XCTAssertEqual(GameBuildSetup.action(inputs: inputs, running: false), .chooseFiles)
        }
    }

    func testActiveBuildOpensProgressWithoutChangingItsFiles() {
        for inputs in [[String: [String]](), ["folder": ["/games/another"]]] {
            XCTAssertEqual(GameBuildSetup.action(inputs: inputs, running: true), .showProgress)
        }
    }
}
