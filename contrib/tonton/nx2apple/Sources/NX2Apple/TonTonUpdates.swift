import AppKit
import SwiftUI
import NXModel

/// The same per-game build receipts the maintenance runner writes. Reading these
/// never opens game data or saves and does not disturb the launcher's own queue.
struct TonTonUpdates: View {
    @EnvironmentObject var loc: Localizer
    private struct Job: Decodable, Identifiable {
        let title: String
        let name: String
        let state: String
        let detail: String?
        let log: String?
        var id: String { title }
    }
    private struct Report: Decodable { let jobs: [Job] }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            if let path = Bundle.main.object(forInfoDictionaryKey: "TonTonUpdateReport") as? String,
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let report = try? JSONDecoder().decode(Report.self, from: data), !report.jobs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label(loc.t("tonton.updates"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                    Text(loc.t("tonton.updatesNote")).font(.footnote).foregroundStyle(.secondary)
                    ForEach(report.jobs) { job in
                        HStack(alignment: .top) {
                            Image(systemName: job.state == "installed" ? "checkmark.circle.fill" : job.state == "running" ? "hammer.fill" : "circle")
                                .foregroundStyle(job.state == "installed" ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(job.name)
                                Text(loc.t("tonton.state." + job.state)).font(.caption).foregroundStyle(.secondary)
                                if let detail = job.detail, !detail.isEmpty {
                                    Text(loc.t("tonton.phase." + detail)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let log = job.log, FileManager.default.fileExists(atPath: log) {
                                Button(loc.t("tonton.viewLog")) { NSWorkspace.shared.open(URL(fileURLWithPath: log)) }
                            }
                        }
                    }
                }.padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}
