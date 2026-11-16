import Foundation

/// Setting up an unbuilt game remains possible before its files are associated.
/// A running build owns the form, so that action opens its progress instead.
package enum GameBuildSetup: Equatable {
    case chooseFiles, configure, showProgress

    package static func hasInputs(_ inputs: [String: [String]]) -> Bool {
        ["base", "folder"].contains { key in inputs[key, default: []].contains { !$0.isEmpty } }
    }

    package static func action(inputs: [String: [String]], running: Bool) -> Self {
        running ? .showProgress : hasInputs(inputs) ? .configure : .chooseFiles
    }

    package var buttonKey: String {
        switch self {
        case .chooseFiles: return "launch.chooseBuildFiles"
        case .configure: return "library.setUpBuild"
        case .showProgress: return "launch.showCurrentBuild"
        }
    }

    package var noteKey: String {
        switch self {
        case .chooseFiles: return "launch.missingBuildFiles"
        case .configure: return "launch.noBuild"
        case .showProgress: return "launch.buildInProgress"
        }
    }
}
