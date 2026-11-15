import Foundation

/// Status from the registered checkpoint runner. A refresh never starts work.
package struct DeviceBuildReport: Decodable, Sendable {
    package let jobs: [DeviceBuildJob]
}

package struct DeviceBuildJob: Decodable, Identifiable, Sendable {
    package let id: String
    package let title: String
    package let name: String
    package let devices: [String]
    package let state: String
    package let detail: String
    package let completed: Int
    package let total: Int
    package let canResume: Bool
    private let canPauseOverride: Bool?
    package let log: String
    package let folder: String
    package let freeBytes: Int64?
    package let reserveBytes: Int64?
    package let updated: String?
    package let kind: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, name, devices, state, detail, completed, total, canResume
        case log, folder, freeBytes, reserveBytes, updated, kind
        case canPauseOverride = "canPause"
    }

    package var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    package var remaining: Int { max(0, total - completed) }
    package var isTransfer: Bool { kind == "transfer" }
    package var canPause: Bool { canPauseOverride ?? ["running", "waiting", "waiting_space"].contains(state) }
}
