import XCTest
@testable import NXCore
@testable import NXModel

@MainActor final class DeviceBuildStoreTests: XCTestCase {
    private let report = """
    {"jobs":[{"id":"m2-test","title":"test","name":"Test","devices":["M2"],"state":"paused","detail":"paused_by_player","completed":50,"total":100,"canResume":true,"log":"/tmp/test/log","folder":"/tmp/test"}]}
    """

    func testRefreshIsReadOnlyAndResumeKeepsRegisteredJobIdentity() async throws {
        let runner = FakeProcessRunner()
        runner.answer = { [report] _ in ProcessResult(out: report) }
        let store = DeviceBuildStore(python: "/python", script: "/controller", config: "/config with spaces.json", runner: runner)
        await store.refresh()?.value
        XCTAssertEqual(store.jobs.first?.fraction, 0.5)
        XCTAssertEqual(runner.launches.first?.arguments, ["/controller", "--config", "/config with spaces.json", "status"])
        let job = try XCTUnwrap(store.jobs.first)
        await store.resume(job)?.value
        XCTAssertEqual(runner.launches.last?.arguments, ["/controller", "--config", "/config with spaces.json", "resume", "--job", "m2-test"])
        XCTAssertFalse(store.busy)
        XCTAssertEqual(store.error, "")
    }

    func testFailureKeepsLastKnownCheckpointAndShowsError() async {
        let runner = FakeProcessRunner()
        runner.answer = { [report] _ in ProcessResult(out: report) }
        let store = DeviceBuildStore(python: "/python", script: "/controller", config: "/config", runner: runner)
        await store.refresh()?.value
        runner.answer = { _ in ProcessResult(status: 1, err: "Lineage changed") }
        await store.refresh()?.value
        XCTAssertEqual(store.jobs.first?.completed, 50)
        XCTAssertEqual(store.error, "Lineage changed")
        XCTAssertFalse(store.busy)
    }
}
