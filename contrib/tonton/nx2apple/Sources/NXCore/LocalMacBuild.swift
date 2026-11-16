import Foundation

/// Verified local inputs and retained work directories for imported TonTon games.
/// An unrelated folder or another version never inherits these build settings.
package struct LocalMacBuild: Codable, Equatable, Sendable {
    package let sourceDirectory: String
    package let workDirectory: String
    package let outputDirectory: String
    package let version: Int
    package let name: String
    package let bundleID: String
    package let language: String
    package let icon: String
    package let profileDirectories: [String]
    package var nvnCapture: String?

    package static func registered(titleID: String, file: String? = ProcessInfo.processInfo.environment["TONTON_BUILD_CONFIG"]) -> Self? {
        guard let file, let data = FileManager.default.contents(atPath: file) else { return nil }
        return (try? JSONDecoder().decode([String: Self].self, from: data))?[titleID]
    }

    package static func load(titleID: String, source: String, file: String? = ProcessInfo.processInfo.environment["TONTON_BUILD_CONFIG"]) -> Self? {
        guard let config = registered(titleID: titleID, file: file),
              URL(fileURLWithPath: source).resolvingSymlinksInPath().standardizedFileURL.path ==
                URL(fileURLWithPath: config.sourceDirectory).resolvingSymlinksInPath().standardizedFileURL.path else { return nil }
        return config
    }

    /// Change only the registered location. The version, output, profiles and caches belong to the game.
    package static func replaceSource(titleID: String, with source: String,
                                      file: String? = ProcessInfo.processInfo.environment["TONTON_BUILD_CONFIG"]) throws {
        guard let file, FileManager.default.fileExists(atPath: file) else { return }
        let url = URL(fileURLWithPath: file)
        guard var configs = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard var config = configs[titleID], config["sourceDirectory"] as? String != source else { return }
        config["sourceDirectory"] = source
        configs[titleID] = config
        try JSONSerialization.data(withJSONObject: configs, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }

    package var arguments: [String] {
        ["-p", "v\(version)", "--app-name", name, "--bundle-id", bundleID,
         "--language", language, "--icon", icon, "--mac-compact-shaders", "--no-heap-check", "--no-prebake"]
    }

    package var environment: [String: String] {
        var env = ["J": "6", "DMSH_CAS": workDirectory + "/shader/cache/cas.zstd.db"]
        if !profileDirectories.isEmpty {
            env["DM_GAMES_DIR"] = profileDirectories.joined(separator: ":")
            env["DM_GAMES_FIRST"] = "1"
        }
        if let nvnCapture { env["DM_NVN_CAPTURE"] = nvnCapture }
        return env
    }

    package static func updating(titleID: String, report: String? = ProcessInfo.processInfo.environment["TONTON_UPDATE_REPORT"]) -> Bool {
        guard let report, let data = FileManager.default.contents(atPath: report),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobs = json["jobs"] as? [[String: Any]] else { return false }
        return jobs.contains { $0["title"] as? String == titleID && ["queued", "running", "ready"].contains($0["state"] as? String ?? "") }
    }
}
