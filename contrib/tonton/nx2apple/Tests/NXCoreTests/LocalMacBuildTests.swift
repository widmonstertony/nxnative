import XCTest
@testable import NXCore

final class LocalMacBuildTests: XCTestCase {
    func testOnlyTheVerifiedSourceReusesTheWorkDirectoryAndVersion() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let config = LocalMacBuild(sourceDirectory: root.appendingPathComponent("input").path,
                                   workDirectory: root.appendingPathComponent("retained-work").path,
                                   outputDirectory: root.appendingPathComponent("games").path,
                                   version: 131072, name: "Example", bundleID: "com.example.game",
                                   language: "zh-Hans", icon: root.appendingPathComponent("icon.png").path,
                                   profileDirectories: ["/tmp/custom-profile"], nvnCapture: "/tmp/nvn")
        let file = root.appendingPathComponent("builds.json")
        try JSONEncoder().encode(["0400486024DEC000": config]).write(to: file)
        XCTAssertEqual(LocalMacBuild.load(titleID: "0400486024DEC000", source: config.sourceDirectory, file: file.path), config)
        XCTAssertNil(LocalMacBuild.load(titleID: "0400486024DEC000", source: root.appendingPathComponent("another-version").path, file: file.path))
        XCTAssertNil(LocalMacBuild.load(titleID: "0100000000010000", source: config.sourceDirectory, file: file.path))
        XCTAssertTrue(config.arguments.contains("v131072"))
        XCTAssertEqual(config.environment["DM_NVN_CAPTURE"], "/tmp/nvn")
    }
}
