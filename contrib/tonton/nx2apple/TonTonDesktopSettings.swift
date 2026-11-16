import AppKit
import SwiftUI

/// Uses the same profile and preference domain as the standalone game.
public struct TonTonDesktopSettings: View {
    @StateObject private var model: LauncherModel
    private let rows: [[String]]
    private let movement: String
    private let defaults: UserDefaults
    @Environment(\.dismiss) private var dismiss

    public init(appPath: String) {
        let app = URL(fileURLWithPath: appPath)
        let bundle = Bundle(url: app)
        let defaults = bundle?.bundleIdentifier.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        let dm = app.appendingPathComponent("Contents/Resources/dm")
        let data = (try? Data(contentsOf: dm.appendingPathComponent("launcher.json"))) ?? Data()
        let settings = (try? JSONDecoder().decode(SettingsFile.self, from: data))?.settings ?? []
        let title = bundle?.object(forInfoDictionaryKey: "DMTitleID") as? String ?? ""
        let player = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/nxnative").appendingPathComponent(title)
        var environment: [String: String] = [:]
        for url in [player, dm].map({ $0.appendingPathComponent("env.txt") }) {
            for line in ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n") {
                let text = line.trimmingCharacters(in: .whitespaces)
                guard !text.hasPrefix("#"), let equals = text.firstIndex(of: "=") else { continue }
                let key = text[..<equals].trimmingCharacters(in: .whitespaces)
                if environment[key] == nil { environment[key] = String(text[text.index(after: equals)...]) }
            }
        }
        environment["DM_ENV_FILE_KEYS"] = environment.keys.sorted().joined(separator: " ")
        _model = StateObject(wrappedValue: LauncherModel(settings, defaults: defaults, environment: environment))
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
                if !model.fixed.contains("DM_KEYMAP") && !model.ignoreSaved {
                    let value = model.values["DM_KEYMAP"] ?? ""
                    if value.isEmpty { defaults.removeObject(forKey: "launcher.DM_KEYMAP") }
                    else { defaults.set(value, forKey: "launcher.DM_KEYMAP") }
                }
                dismiss()
            }.keyboardShortcut(.defaultAction).padding()
        }.frame(width: 620, height: 650)
    }
}
