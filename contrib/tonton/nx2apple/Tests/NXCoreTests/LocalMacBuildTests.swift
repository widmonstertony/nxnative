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

        let newSource = root.appendingPathComponent("external/game.nup").path
        try LocalMacBuild.replaceSource(titleID: "0400486024DEC000", with: newSource, file: file.path)
        XCTAssertNil(LocalMacBuild.load(titleID: "0400486024DEC000", source: config.sourceDirectory, file: file.path))
        let moved = try XCTUnwrap(LocalMacBuild.load(titleID: "0400486024DEC000", source: newSource, file: file.path))
        XCTAssertEqual(moved.workDirectory, config.workDirectory)
        XCTAssertEqual(moved.outputDirectory, config.outputDirectory)
        XCTAssertEqual(moved.arguments, config.arguments)
        XCTAssertEqual(moved.environment, config.environment)
    }

    func testShaderInputsCheckSelectedProfileBeforeRequiringCapturePairs() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let titleID = "0100B3F000BE2000"
        let work = root.appendingPathComponent("cache")
        let profiles = root.appendingPathComponent("profiles")
        let profile = profiles.appendingPathComponent(titleID)
        let capture = root.appendingPathComponent("captures")
        let config = LocalMacBuild(sourceDirectory: root.path, workDirectory: work.path, outputDirectory: root.path,
                                   version: 0, name: "Example", bundleID: "com.example.game",
                                   language: "zh-Hans", icon: "", profileDirectories: [work.appendingPathComponent("profile").path, profiles.path],
                                   nvnCapture: capture.path)
        for directory in [profile, capture, work.appendingPathComponent("profile/\(titleID)")] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data().write(to: work.appendingPathComponent("profile/\(titleID)/game.tsv"))
        try Data().write(to: profile.appendingPathComponent("game.tsv"))
        let key = "0123456789abcdef"
        let map = "ps_other.bin\t0\tpixel\t\(key)\t/nvn_capture/\(key)\n"
        try map.write(to: profile.appendingPathComponent("shader_map.tsv"), atomically: true, encoding: .utf8)
        let conflict = profile.appendingPathComponent("shader_map.tsv.conflicts.tsv")
        XCTAssertEqual(config.shaderInputProblem(titleID: titleID, engine: ""), .missingConflictTable(conflict.path))
        try Data().write(to: conflict)
        try Data().write(to: capture.appendingPathComponent(key + ".ctl"))
        XCTAssertEqual(config.shaderInputProblem(titleID: titleID, engine: ""),
                       .missingCaptures(directory: capture.path, keys: [key]))
        try Data().write(to: capture.appendingPathComponent(key + ".code"))
        XCTAssertNil(config.shaderInputProblem(titleID: titleID, engine: ""))
    }
}
