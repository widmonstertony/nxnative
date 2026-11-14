import Foundation

/// Deployment targets are part of the build identity, never an Info.plist-only patch.
package enum IOSBuildTarget: String, CaseIterable, Sendable {
    case ios16 = "16.1", ios17 = "17.0", modern = "26.0"
    package static func normalized(_ value: String?) -> Self { Self(rawValue: value ?? "") ?? .ios16 }
    package var compatibility: Bool { self != .modern }
    package var outputSuffix: String { "-ios" + rawValue }
    package var workSuffix: String { compatibility ? "/ios-" + rawValue + "-classic-b5ac83de" : "/ios-26-modern" }
}
