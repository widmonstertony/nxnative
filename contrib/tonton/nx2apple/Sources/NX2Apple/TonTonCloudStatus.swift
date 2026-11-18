import SwiftUI
import NXModel

struct TonTonCloudStatus: View {
    enum Transport {
        case original, folder, local

        init(playerIsDefault: Bool, overrides: [String: String], envFiles: [String: String]) {
            if !playerIsDefault {
                self = .local
            } else if GameboxCloud.usesOriginalBackups(overrides: overrides, settings: envFiles) {
                self = .original
            } else if let folder = overrides["DM_SAVE_SYNC"] ?? envFiles["DM_SAVE_SYNC"], !folder.isEmpty, folder != "0" {
                self = .folder
            } else {
                self = .local
            }
        }

        var labelKey: String {
            switch self {
            case .original: "tonton.syncOriginal"
            case .folder: "tonton.syncFolder"
            case .local: "tonton.syncLocal"
            }
        }
    }

    var titleIDs: [String] = []
    var transport: Transport?
    @EnvironmentObject var loc: Localizer
    @State private var backups: Int?
    @State private var failure = false
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(loc.t("tonton.icloud"), systemImage: "icloud")
                .font(.headline)
            Text(loc.t(failure ? "tonton.icloudUnavailable" : backups != nil ? "tonton.icloudReady" : "tonton.icloudChecking"))
            if let transport {
                Text(loc.t(transport.labelKey)).font(.subheadline.weight(.semibold))
            }
            if !failure, let backups, !titleIDs.isEmpty {
                Text(transport == nil ? String(format: loc.t("tonton.icloudBackups"), backups) :
                     loc.t(backups > 0 ? "tonton.icloudGameFound" : "tonton.icloudGameMissing")).font(.subheadline)
            }
            Text(loc.t("tonton.icloudNote")).font(.footnote).foregroundStyle(.secondary)
            Button(loc.t("tonton.icloudCheck")) { Task { await refresh() } }
                .disabled(checking)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .task { await refresh() }
    }

    @MainActor private func refresh() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let titles = titleIDs
        do {
            backups = try await Task.detached { try await GameboxCloud.inspectBackups(titles: titles) }.value
            failure = false
        } catch { failure = true }
    }
}
