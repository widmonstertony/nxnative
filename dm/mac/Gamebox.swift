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

@main
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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
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
                        Text("\(games.filter { $0.app != nil }.count) / \(games.count)")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        Text("可启动").font(.caption).foregroundStyle(.secondary)
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 174), spacing: 16)], alignment: .leading, spacing: 22) {
                        ForEach(games) { game in
                            Button { open(game) } label: { GameCard(game: game) }
                                .buttonStyle(.plain)
                                .disabled(game.app == nil)
                                .help(game.app == nil ? "待构建" : "启动 \(game.name)")
                        }
                    }
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
        .alert("无法启动游戏", isPresented: Binding(get: { launchError != nil }, set: { if !$0 { launchError = nil } })) {
            Button("好", role: .cancel) { launchError = nil }
        } message: {
            Text(launchError ?? "")
        }
    }

    private func open(_ game: Game) {
        guard let app = game.app else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, error in
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
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
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
