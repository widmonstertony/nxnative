import XCTest
@testable import NXCore

final class IOSBuildTargetTests: XCTestCase {
    func testDeploymentTargetsNeverShareBuildProducts() {
        XCTAssertEqual(IOSBuildTarget.normalized(nil), .ios16)
        XCTAssertEqual(IOSBuildTarget.normalized("17.0"), .ios17)
        XCTAssertTrue(IOSBuildTarget.ios16.compatibility)
        XCTAssertFalse(IOSBuildTarget.modern.compatibility)
        XCTAssertEqual(Set(IOSBuildTarget.allCases.map(\.workSuffix)).count, 3)
        XCTAssertEqual(Set(IOSBuildTarget.allCases.map(\.outputSuffix)).count, 3)
    }

    func testQueuePersistsDeploymentAndReadsOldEntries() throws {
        let entry = QueueEntry(titleID: "test", name: "Test", target: BuildTarget.ios, inputs: [:],
                               iosMinimum: "17.0", outputDirectory: "/out", engineID: "engine")
        let data = try JSONEncoder().encode(entry)
        XCTAssertEqual(try JSONDecoder().decode(QueueEntry.self, from: data).iosMinimum, "17.0")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "iosMinimum")
        let decoded = try JSONDecoder().decode(QueueEntry.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(IOSBuildTarget.normalized(decoded.iosMinimum), .ios16)
    }
}
