import AppKit
import SwiftUI

private struct Game: Decodable, Identifiable {
    let id: String
    let name: String
    var app: URL? = nil

    private enum CodingKeys: String, CodingKey { case id, name }

    init(id: String, name: String, app: URL) {
        self.id = id
        self.name = name
        self.app = app
    }
}

private func gameLibrary() -> [Game] {
    let fm = FileManager.default
    let catalog = Bundle.main.url(forResource: "GameCatalog", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode([Game].self, from: $0) } ?? []
    var installed: [String: Game] = [:]
    for root in fm.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask]) {
        let apps = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for url in apps.sorted(by: { $0.path < $1.path }) where url.pathExtension == "app" {
            guard let bundle = Bundle(url: url),
                  let titleID = bundle.object(forInfoDictionaryKey: "DMTitleID") as? String,
                  titleID.range(of: "^[0-9A-Fa-f]{16}$", options: .regularExpression) != nil,
                  let executable = bundle.executableURL, fm.isExecutableFile(atPath: executable.path) else { continue }
            let id = titleID.uppercased()
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            installed[id] = Game(id: id, name: name, app: url)
        }
    }
    let planned = catalog.map { game -> Game in
        guard let ready = installed.removeValue(forKey: game.id) else { return game }
        var result = game
        result.app = ready.app
        return result
    }
    return planned + installed.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

private func gameIcon(_ app: URL) -> NSImage {
    if let bundle = Bundle(url: app),
       let name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
       let url = bundle.url(forResource: name, withExtension: nil) ?? bundle.url(forResource: name, withExtension: "icns"),
       let icon = NSImage(contentsOf: url) {
        return icon
    }
    return NSWorkspace.shared.icon(forFile: app.path)
}

private struct GameSettings: Identifiable {
    let game: Game
    let app: URL
    let version: String
    let cloudKitContainer: String?
    let defaults: UserDefaults
    let model: LauncherModel
    let environment: [String: String]
    var id: String { game.id }

    init?(_ game: Game) {
        guard let app = game.app, let bundle = Bundle(url: app),
              let domain = bundle.bundleIdentifier, let defaults = UserDefaults(suiteName: domain),
              let dm = bundle.resourceURL?.appendingPathComponent("dm"),
              let data = try? Data(contentsOf: dm.appendingPathComponent("launcher.json")),
              let file = try? JSONDecoder().decode(SettingsFile.self, from: data),
              !file.settings.isEmpty else { return nil }
        self.game = game
        self.app = app
        self.version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        self.cloudKitContainer = bundle.object(forInfoDictionaryKey: "DMCloudSaveContainer") as? String
        self.defaults = defaults
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/nxnative")
            .appendingPathComponent(game.id)
        let env = Self.readEnvironment([support, dm].map { $0.appendingPathComponent("env.txt") })
        self.environment = env
        self.model = LauncherModel(file.settings, defaults: defaults, environment: env)
    }

    // Match launcher.c: the user's file takes precedence and the first definition wins.
    private static func readEnvironment(_ urls: [URL]) -> [String: String] {
        let whitespace = CharacterSet(charactersIn: " \t\r")
        var result: [String: String] = [:]
        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for rawLine in text.components(separatedBy: "\n") {
                let line = rawLine.trimmingCharacters(in: whitespace)
                guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
                let key = line[..<equals].trimmingCharacters(in: whitespace)
                guard !key.isEmpty, result[key] == nil else { continue }
                result[key] = String(line[line.index(after: equals)...])
            }
        }
        result["DM_ENV_FILE_KEYS"] = result.keys.sorted().joined(separator: " ")
        result["DM_ENV_LAUNCH_KEYS"] = ""
        return result
    }
}

struct TonTonGamebox: App {
    var body: some Scene {
        Window("TonTon游戏匣", id: "library") {
            GameboxLibrary()
                .frame(minWidth: 620, minHeight: 470)
        }
        .defaultSize(width: 860, height: 680)
    }
}

private struct GameboxLibrary: View {
    @State private var games: [Game] = []
    @State private var launchError: String?
    @State private var settings: GameSettings?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let installed = games.filter { $0.app != nil }
        let pending = games.filter { $0.app == nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.red).frame(width: 5, height: 63)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TONTON  /  GAME CARDS")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.red)
                        Text("TonTon游戏匣").font(.system(size: 32, weight: .heavy))
                        Text("打开你的游戏卡带").foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 4) {
                        Text("\(installed.count) / \(games.count)")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        Text("已安装 / 游戏总数").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

                if games.isEmpty {
                    ContentUnavailableView("还没有卡带", systemImage: "gamecontroller",
                                           description: Text("已安装的 nxnative macOS 游戏会显示在这里。"))
                        .padding(.vertical, 45)
                } else {
                    if !installed.isEmpty { gameGrid("已安装", games: installed) }
                    if !pending.isEmpty { gameGrid("待构建", games: pending) }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            Button("刷新游戏", systemImage: "arrow.clockwise") { games = gameLibrary() }
                .keyboardShortcut("r")
        }
        .onAppear { games = gameLibrary() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { games = gameLibrary() } }
        .sheet(item: $settings) { state in
            LauncherView(m: state.model, name: state.game.name, version: state.version,
                         icon: gameIcon(state.app), cancelTitle: "Cancel",
                         environment: state.environment, cloudKitContainer: state.cloudKitContainer,
                         managedCloudSync: GameboxCloud.enabled && state.environment["DM_SAVE"] == nil && state.environment["DM_ROOT"] == nil,
                         desktopProfile: state.app.appendingPathComponent("Contents/Resources/dm/desktop.tsv"),
                         done: { play in
                settings = nil
                if play {
                    state.model.saveChoices()
                    open(state.game, skipSettings: true)
                }
            }, fit: { _ in })
            .defaultAppStorage(state.defaults)
            .frame(width: 560, height: 620)
        }
        .alert("游戏匣", isPresented: Binding(get: { launchError != nil }, set: { if !$0 { launchError = nil } })) {
            Button("好", role: .cancel) { launchError = nil }
        } message: {
            Text(launchError ?? "")
        }
    }

    private func gameGrid(_ title: String, games: [Game]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(title) · \(games.count)").font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 174), spacing: 16)], alignment: .leading, spacing: 22) {
                ForEach(games) { game in
                    VStack(alignment: .leading, spacing: 6) {
                        Button { play(game) } label: { GameCard(game: game) }
                            .buttonStyle(.plain)
                            .disabled(game.app == nil)
                            .help(game.app == nil ? "待构建" : "启动 \(game.name)")
                        if let app = game.app {
                            HStack {
                                Button("游戏设置", systemImage: "gearshape") { showSettings(game) }
                                    .help("打开 \(game.name) 的启动设置")
                                Menu {
                                    Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([app]) }
                                    Button("查看运行日志") { showLog(game) }
                                    if GameboxCloud.enabled {
                                        Button("查看 iCloud 同步日志") { showLog(game, cloud: true) }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .fixedSize()
                                .accessibilityLabel("更多游戏操作")
                            }
                        }
                    }
                }
            }
        }
    }

    private func showSettings(_ game: Game) {
        if let state = GameSettings(game) { settings = state }
        else { launchError = "这款游戏的应用没有可读取的启动设置。你仍可直接启动游戏。" }
    }

    private func play(_ game: Game) {
        if let state = GameSettings(game),
           (state.defaults.object(forKey: "window.show") as? Bool) != false || NSEvent.modifierFlags.contains(.option) {
            settings = state
        } else {
            open(game, skipSettings: true)
        }
    }

    private func showLog(_ game: Game, cloud: Bool = false) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/nxnative")
            .appendingPathComponent(game.id + (cloud ? ".icloud.log" : ".log"))
        if !NSWorkspace.shared.open(url) { launchError = "还没有可打开的运行日志。" }
    }

    private func open(_ game: Game, skipSettings: Bool = false) {
        guard let app = game.app else { return }
        if GameboxCloud.enabled {
            do {
                try GameboxCloud.start(title: game.id, app: app, skipSettings: skipSettings)
                return
            } catch {
                launchError = error.localizedDescription
                return
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        if skipSettings { configuration.arguments = ["--no-launcher"] }
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            if let error { Task { @MainActor in launchError = error.localizedDescription } }
        }
    }
}

private struct GameCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 0) {
                Text("TONTON  /  GAME CARD")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.80, green: 0.15, blue: 0.19))
                Group {
                    if let app = game.app {
                        Image(nsImage: gameIcon(app))
                            .resizable().scaledToFit().frame(width: 75, height: 75)
                    } else {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 39, weight: .light))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 106)
                .background(Color(red: 0.10, green: 0.14, blue: 0.19))
                HStack {
                    Text("TTG • MAC")
                    Spacer()
                    Text("▮ ▮ ▮ ▮").foregroundStyle(.yellow.opacity(0.65))
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(8)
            }
            .foregroundStyle(.white)
            .background(Color(red: 0.18, green: 0.20, blue: 0.23))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(game.name).font(.headline).lineLimit(2, reservesSpace: true)
            Label(game.app == nil ? "待构建" : "启动游戏", systemImage: game.app == nil ? "hourglass" : "play.fill")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
