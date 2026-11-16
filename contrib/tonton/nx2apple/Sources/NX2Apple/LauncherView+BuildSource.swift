import AppKit
import UniformTypeIdentifiers
import NXCore

extension LauncherView {
    func chooseBuildSource(_ game: LibraryGame) {
        guard !m.running else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "nup") ?? .data]
        panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        panel.message = loc.t("library.buildSourceHint")
        panel.prompt = loc.t("library.buildSourceChoose")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.standardizedFileURL.path
        let title = game.titleID.uppercased()
        let config = LocalMacBuild.registered(titleID: title)
        var updated = game
        let source: String
        if GameFolder.isCandidate(path) || url.pathExtension.lowercased() == "nup" {
            let contents: GameFolder.Contents
            switch GameFolder.scan(path) {
            case .failure(let problem): launchError = m.gameFolderProblemText(problem); return
            case .success(let result): contents = result
            }
            guard contents.titleIDHex == title else {
                launchError = loc.t("library.buildSourceWrongGame"); return
            }
            if let config, config.version > 0, !contents.updates.contains(where: { $0.version == config.version }) {
                launchError = String(format: loc.t("library.buildSourceMissingVersion"), String(config.version)); return
            }
            source = contents.scriptInput
            updated.inputs = [GameLibrary.folderInput: [source], "base": [contents.basePath]]
            updated.sourceFolder = source
        } else {
            guard let titleID = UInt64(title, radix: 16) else { return }
            let types = GameInputs.allowedFileTypes(for: .update)
            let packages = GameInputs.inputFiles(in: path).filter {
                types.contains(($0 as NSString).pathExtension.lowercased()) &&
                    TitleID.parse(($0 as NSString).lastPathComponent).map(TitleID.owner) == titleID
            }
            let found = GameInputs.classify(packages)
            guard let base = found.base else { launchError = loc.t("library.buildSourceWrongGame"); return }
            var update = found.update
            if let config, config.version > 0 {
                update = packages.first {
                    let name = ($0 as NSString).lastPathComponent
                    return TitleID.parse(name) == (titleID | 0x800) && TitleID.updateVersion(name) == config.version
                } ?? update
            }
            source = (base as NSString).deletingLastPathComponent
            updated.inputs = ["base": [base], "update": update.map { [$0] } ?? [], "dlc": found.dlc]
            updated.sourceFolder = path
        }
        updated.preferredBuildSource = path
        updated.lastTarget = BuildTarget.mac
        guard library.upsert(updated) else { library.upsert(game); return }
        do {
            try LocalMacBuild.replaceSource(titleID: title, with: source)
        } catch {
            library.upsert(game)
            launchError = error.localizedDescription
            return
        }
        configureBuild(updated)
    }
}
