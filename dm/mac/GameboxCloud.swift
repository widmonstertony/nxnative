import AppKit
import CloudKit
import CryptoKit
import Darwin

@_silgen_name("save_sync_mount")
private func syncMount(_ save: UnsafePointer<CChar>, _ title: UnsafePointer<CChar>) -> Int32
@_silgen_name("save_sync_flush")
private func syncFlush(_ timeout: Int32) -> Int32
@_silgen_name("save_sync_after_exit")
private func syncAfterExit(_ save: UnsafePointer<CChar>, _ title: UnsafePointer<CChar>) -> Int32
@_silgen_name("front_cloudkit_account")
private func syncAccount(_ scope: UnsafeMutablePointer<CChar>) -> Int32

@main
enum GameboxMain {
    @MainActor static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--cloud-game" {
            await GameboxCloud.run(args)
        } else if args.first == "--cloud-status", args.count <= 2 {
            await GameboxCloud.status(title: args.dropFirst().first)
        } else {
            TonTonGamebox.main()
        }
    }
}

enum GameboxCloud {
    private static var container: String? {
        (Bundle.main.object(forInfoDictionaryKey: "DMCloudSaveContainer") as? String)
            .flatMap { $0.hasPrefix("iCloud.") ? $0 : nil }
    }
    static var enabled: Bool { container != nil }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static func valid(_ title: String) -> Bool {
        title.range(of: "^[0-9A-F]{16}$", options: .regularExpression) != nil
    }

    @discardableResult
    static func start(title: String, app: URL, skipSettings: Bool, environment: [String: String] = [:]) throws -> Process {
        guard valid(title), let exe = Bundle.main.executableURL else { throw NSError(domain: "TonTon", code: 2) }
        let logDir = home.appendingPathComponent("Library/Logs/nxnative")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let path = logDir.appendingPathComponent(title + ".icloud.log").path
        let fd = Darwin.open(path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let log = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let worker = Process()
        worker.executableURL = exe
        worker.arguments = ["--cloud-game", title, app.path, skipSettings ? "1" : "0"]
        var inherited = ProcessInfo.processInfo.environment
        inherited["TONTON_GAME_ENV"] = String(data: try JSONEncoder().encode(environment), encoding: .utf8)
        worker.environment = inherited
        worker.standardOutput = log
        worker.standardError = log
        try worker.run()
        return worker
    }

    static func status(title: String?) async {
        guard let name = container else { print("CloudKit not configured"); exit(2) }
        do {
            let ck = CKContainer(identifier: name)
            guard try await ck.accountStatus() == .available else { exit(3) }
            let user = try await ck.userRecordID()
            let hash = SHA256.hash(data: Data("\(name):\(user.recordName)".utf8))
            let scope = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
            var transportScope = [CChar](repeating: 0, count: 33)
            let transportMatches = transportScope.withUnsafeMutableBufferPointer {
                syncAccount($0.baseAddress!) != 0 && String(cString: $0.baseAddress!) == scope
            }
            guard transportMatches else { print("CloudKit sync transport did not match the account"); exit(5) }
            if let title {
                guard valid(title) else { exit(2) }
                let id = CKRecord.ID(recordName: "save1-\(scope)-\(title)")
                let records = try await ck.privateCloudDatabase.records(for: [id], desiredKeys: ["digest"])
                guard let result = records[id] else { exit(5) }
                let record = try result.get()
                guard record.recordType == "TonTonSaveV1", record["digest"] is String else { exit(5) }
                print("Existing TonTon backup confirmed for \(title)")
            }
            print("CloudKit account available for \(name)")
        } catch {
            let e = error as NSError
            print("CloudKit error \(e.domain) \(e.code)")
            exit(4)
        }
    }

    @MainActor private static func running(_ id: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first { !$0.isTerminated }
    }

    @MainActor static func run(_ args: [String]) async {
        guard enabled, args.count == 4, valid(args[1]), ["0", "1"].contains(args[3]) else { return }
        let title = args[1]
        let app = URL(fileURLWithPath: args[2]).standardizedFileURL
        let fm = FileManager.default
        let roots = fm.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        guard roots.contains(where: { $0.standardizedFileURL.path == app.deletingLastPathComponent().path }),
              let bundle = Bundle(url: app), let id = bundle.bundleIdentifier,
              (bundle.object(forInfoDictionaryKey: "DMTitleID") as? String)?.uppercased() == title else { return }
        if let game = running(id) { game.activate(); return }
        let support = home.appendingPathComponent("Library/Application Support/nxnative")
            .appendingPathComponent(title)
        do {
            try fm.createDirectory(at: support, withIntermediateDirectories: true)
            let lock = Darwin.open(support.appendingPathComponent(".tonton-cloud.lock").path,
                                   O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard lock >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            defer { close(lock) }
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { return }
            if let game = running(id) { game.activate(); return }
            let envFiles = [support.appendingPathComponent("env.txt"),
                            bundle.resourceURL?.appendingPathComponent("dm/env.txt")].compactMap { $0 }
            var settings: [String: String] = [:]
            for url in envFiles {
                guard let value = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for line in value.split(separator: "\n") {
                    let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard parts.count == 2 else { continue }
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    if settings[key] == nil { settings[key] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines) }
                }
            }
            let launchData = ProcessInfo.processInfo.environment["TONTON_GAME_ENV"]?.data(using: .utf8)
            let overrides = launchData.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            // Custom player saves and explicit folder transports retain their own location.
            // The managed path and the standalone launcher must agree on the save location.
            let useCloud = overrides["DM_SAVE"] == nil && overrides["DM_ROOT"] == nil
                && overrides["DM_SAVE_SYNC"] == nil
                && settings["DM_SAVE"] == nil && settings["DM_ROOT"] == nil
                && settings["DM_SAVE_SYNC"] != "0"
            let save = support.appendingPathComponent("save").path
            var compared = false
            if useCloud {
                unsetenv("DM_SAVE_SYNC")
                setenv("DM_SAVE_SYNC_CHOICE", "ask", 1)
                guard syncMount(save, title) == 0 else {
                    fputs("TonTon: interrupted save recovery is incomplete; game launch stopped to keep the save intact\n", stderr)
                    return
                }
                compared = syncFlush(18_000) != 0
            }
            let configuration = NSWorkspace.OpenConfiguration()
            if args[3] == "1" { configuration.arguments = ["--no-launcher"] }
            var launchEnvironment: [String: String] = [:]
            if let data = ProcessInfo.processInfo.environment["TONTON_GAME_ENV"]?.data(using: .utf8) {
                launchEnvironment = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            }
            if useCloud { launchEnvironment["DM_SAVE_SYNC"] = "0" }
            configuration.environment = launchEnvironment
            if let game = running(id) { game.activate(); return }
            let game = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
            while !game.isTerminated { try await Task.sleep(for: .seconds(1)) }
            if compared { _ = syncAfterExit(save, title) }
        } catch {
            FileHandle.standardError.write(Data("TonTon: \(error.localizedDescription)\n".utf8))
        }
    }
}
