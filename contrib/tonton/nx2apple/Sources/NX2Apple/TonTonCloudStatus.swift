import SwiftUI
import NXModel

struct TonTonCloudStatus: View {
    var titleIDs: [String] = []
    @EnvironmentObject var loc: Localizer
    @State private var backups: Int?
    @State private var failure = false
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(loc.t("tonton.icloud"), systemImage: "icloud")
                .font(.headline)
            Text(loc.t(failure ? "tonton.icloudUnavailable" : backups != nil ? "tonton.icloudReady" : "tonton.icloudChecking"))
            if let backups, !titleIDs.isEmpty {
                Text(String(format: loc.t("tonton.icloudBackups"), backups)).font(.subheadline)
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
