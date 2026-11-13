import AppKit
import SwiftUI

/// Uses the same profile and preference domain as the standalone game.
public struct TonTonDesktopSettings: View {
    @StateObject private var model: LauncherModel
    private let rows: [[String]]
    private let movement: String
    @Environment(\.dismiss) private var dismiss

    public init(appPath: String) {
        let app = URL(fileURLWithPath: appPath)
        let bundle = Bundle(url: app)
        let defaults = bundle?.bundleIdentifier.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        let dm = app.appendingPathComponent("Contents/Resources/dm")
        let data = (try? Data(contentsOf: dm.appendingPathComponent("launcher.json"))) ?? Data()
        let settings = (try? JSONDecoder().decode(SettingsFile.self, from: data))?.settings ?? []
        _model = StateObject(wrappedValue: LauncherModel(settings, defaults: defaults, environment: [:]))
        let text = (try? String(contentsOf: dm.appendingPathComponent("desktop.tsv"), encoding: .utf8)) ?? ""
        let parsed = text.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        rows = parsed.filter { $0.count >= 3 && $0[0] != "#" && !$0[0].hasPrefix("#") }
        movement = parsed.first(where: { $0.first == "movement" })?.dropFirst().first ?? "stick"
    }

    public var body: some View {
        VStack(alignment: .leading) {
            ScrollView {
                DesktopControlsView(model: model, rows: rows, movement: movement)
                    .padding(24)
            }
            Button(Bundle.main.localizedString(forKey: "Done", value: "Done", table: "Launcher")) {
                model.saveChoices()
                dismiss()
            }.keyboardShortcut(.defaultAction).padding()
        }.frame(width: 620, height: 650)
    }
}
