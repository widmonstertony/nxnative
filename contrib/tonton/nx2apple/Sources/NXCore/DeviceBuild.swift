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
    package let log: String
    package let folder: String
    package let freeBytes: Int64?
    package let reserveBytes: Int64?
    package let updated: String?

    package var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    package var canPause: Bool { ["running", "waiting", "waiting_space"].contains(state) }
}
