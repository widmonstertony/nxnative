import Foundation
import Combine
import NXCore

/// Adopts the existing device-build supervisors without moving their outputs.
@MainActor package final class DeviceBuildStore: ObservableObject {
    @Published package private(set) var jobs: [DeviceBuildJob] = []
    @Published package private(set) var busy = false
    @Published package private(set) var error = ""
    @Published package private(set) var logText = ""
    private let runner: ProcessRunner
    private let command: [String]
    private let config: String

    package init(python: String, script: String, config: String, runner: ProcessRunner = SystemProcessRunner()) {
        self.runner = runner; self.command = [python, script]; self.config = config
    }

    @discardableResult package func refresh() -> Task<Void, Never>? { perform("status") }
    @discardableResult package func resume(_ job: DeviceBuildJob) -> Task<Void, Never>? { perform("resume", job: job) }
    @discardableResult package func pause(_ job: DeviceBuildJob) -> Task<Void, Never>? { perform("pause", job: job) }
    @discardableResult package func showLog(_ job: DeviceBuildJob) -> Task<Void, Never>? { perform("log", job: job) }

    private func perform(_ operation: String, job: DeviceBuildJob? = nil) -> Task<Void, Never>? {
        guard !busy else { return nil }
        busy = true
        let runner = runner
        let arguments = command + ["--config", config, operation] + (job.map { ["--job", $0.id] } ?? [])
        return Task {
            let result = await Task.detached {
                runner.capture(ProcessLaunch(executable: arguments[0], arguments: Array(arguments.dropFirst()), timeout: 15))
            }.value
            defer { busy = false }
            guard result.ok, let data = result.out.data(using: .utf8) else {
                error = String((result.err + result.out).suffix(2000)); return
            }
            do {
                if operation == "log" {
                    struct Log: Decodable { let text: String }
                    logText = try JSONDecoder().decode(Log.self, from: data).text
                } else {
                    jobs = try JSONDecoder().decode(DeviceBuildReport.self, from: data).jobs
                }
                error = ""
            } catch { self.error = error.localizedDescription }
        }
    }
}
