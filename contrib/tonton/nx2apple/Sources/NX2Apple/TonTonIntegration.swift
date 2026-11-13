import AppKit
import Foundation
import NXCore

enum TonTonBootstrap {
    static func configure() {
        let info = Bundle.main.infoDictionary ?? [:]
        var defaults: [String: Any] = ["onboarding.completed": true, "onboarding.platform": "mac", "autoUpdateApp": false]
        if GameboxCloud.enabled { setenv("TONTON_MANAGED_SAVES", "1", 1) }
        if let repo = info["TonTonEngineSource"] as? String { defaults["repoPath"] = repo }
        if let config = info["TonTonBuildConfig"] as? String { setenv("TONTON_BUILD_CONFIG", config, 1) }
        if let report = info["TonTonUpdateReport"] as? String { setenv("TONTON_UPDATE_REPORT", report, 1) }
        if let developer = info["TonTonXcode"] as? String {
            setenv("DEVELOPER_DIR", developer, 1)
            defaults["launcherXcodeApp"] = URL(fileURLWithPath: developer).deletingLastPathComponent().deletingLastPathComponent().path
        }
        if let python = info["TonTonPython"] as? String {
            let bin = URL(fileURLWithPath: python).deletingLastPathComponent().path
            let dotnet = URL(fileURLWithPath: bin).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("dotnet").path
            setenv("PATH", "\(bin):\(dotnet):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", 1)
            setenv("TONTON_PYTHON", python, 1)
        }
        UserDefaults.standard.register(defaults: defaults)
        importInstalledGames()
    }
    private static func importInstalledGames() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let file = support.appendingPathComponent("TonTon Gamebox/library.json")
        var snapshot = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var games = snapshot["games"] as? [[String: Any]] ?? []
        let catalog = Bundle.main.url(forResource: "GameCatalog", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: String]] } ?? []
        let names = Dictionary(catalog.compactMap { row -> (String, String)? in
            guard let id = row["id"], let name = row["name"] else { return nil }; return (id, name)
        }, uniquingKeysWith: { a, _ in a })
        for found in GameLibrary.installedApps(in: [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]) {
            let app = found.resolvingSymlinksInPath()
            guard let info = try? MacGameBundle.read(app) else { continue }
            if let index = games.firstIndex(where: { $0["titleID"] as? String == info.titleID }) {
                games[index]["appPath"] = app.path
            } else {
                games.append(["id": UUID().uuidString, "titleID": info.titleID, "name": names[info.titleID] ?? info.name,
                              "appPath": app.path, "lastTarget": "mac", "defaultsApplied": true])
            }
        }
        for entry in catalog {
            guard let title = entry["id"], let name = entry["name"], !games.contains(where: { $0["titleID"] as? String == title }) else { continue }
            games.append(["id": UUID().uuidString, "titleID": title, "name": name, "lastTarget": "mac", "defaultsApplied": true])
        }
        if let path = Bundle.main.object(forInfoDictionaryKey: "TonTonBuildConfig") as? String,
           let data = fm.contents(atPath: path),
           let builds = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            for index in games.indices {
                guard let title = games[index]["titleID"] as? String, let build = builds[title],
                      let source = build["sourceDirectory"] as? String, fm.fileExists(atPath: source) else { continue }
                var inputs = games[index]["inputs"] as? [String: [String]] ?? [:]
                if inputs.isEmpty { inputs["folder"] = [source]; games[index]["inputs"] = inputs }
                if (games[index]["sourceFolder"] as? String ?? "").isEmpty { games[index]["sourceFolder"] = source }
                if (games[index]["outputDirectory"] as? String ?? "").isEmpty { games[index]["outputDirectory"] = build["outputDirectory"] }
                games[index]["lastTarget"] = "mac"
            }
        }
        // Earlier imports decoded untouched catalog placeholders with an iOS
        // default, even though this installation is being configured for Mac.
        for index in games.indices {
            guard let title = games[index]["titleID"] as? String, names[title] != nil,
                  (games[index]["inputs"] as? [String: [String]] ?? [:]).isEmpty,
                  ["appPath", "iosAppPath", "ipaPath", "archivePath"].allSatisfy({ (games[index][$0] as? String ?? "").isEmpty }) else { continue }
            games[index]["lastTarget"] = "mac"
        }
        snapshot["games"] = games
        if snapshot["folder"] == nil { snapshot["folder"] = "" }
        if snapshot["folders"] == nil { snapshot["folders"] = [String]() }
        do {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
        } catch { fputs("TonTon: could not import installed game entries: \(error.localizedDescription)\n", stderr) }
    }

}

/// Both launch surfaces retain TonTon's signed, private CloudKit transport.
/// The worker owns synchronization; the frontend still tracks the actual game PID.
enum TonTonLaunch {
    @MainActor static func open(_ game: LibraryGame, environment: [String: String],
                                completion: @escaping (NSRunningApplication?, Error?) -> Void) {
        let app = URL(fileURLWithPath: game.appPath)
        guard GameboxCloud.enabled else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.environment = environment
            NSWorkspace.shared.openApplication(at: app, configuration: configuration, completionHandler: completion)
            return
        }
        guard let identifier = Bundle(url: app)?.bundleIdentifier else {
            completion(nil, NSError(domain: "TonTon", code: 2)); return
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { !$0.isTerminated }) {
            running.activate()
            completion(running, nil)
            return
        }
        do {
            let worker = try GameboxCloud.start(title: game.titleID, app: app,
                                                skipSettings: environment["DM_LAUNCHER"] == "0", environment: environment)
            Task { @MainActor in
                let deadline = Date().addingTimeInterval(120)
                while Date() < deadline {
                    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { !$0.isTerminated }) {
                        completion(running, nil); return
                    }
                    if !worker.isRunning { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                completion(nil, NSError(domain: "TonTon", code: 3, userInfo: [NSLocalizedDescriptionKey:
                    Bundle.main.localizedString(forKey: "tonton.cloudLaunchFailed", value: "The game did not open. Check its iCloud sync log.", table: nil)]))
            }
        } catch { completion(nil, error) }
    }
}
