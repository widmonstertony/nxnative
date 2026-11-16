import AppKit
import SwiftUI
import NXModel

/// The same per-game build receipts the maintenance runner writes. Reading these
/// never opens game data or saves and does not disturb the launcher's own queue.
struct TonTonUpdates: View {
    @EnvironmentObject var loc: Localizer
    @State private var cancelError = false
    private struct Job: Decodable, Identifiable {
        let title: String
        let name: String
        let state: String
        let detail: String?
        let log: String?
        let cancelToken: UUID?
        var id: String { title }
    }
    private struct Report: Decodable { let jobs: [Job] }

    private func cancelRequest(for job: Job, reportPath: String) -> URL? {
        guard job.state == "running", let token = job.cancelToken else { return nil }
        return URL(fileURLWithPath: reportPath).deletingLastPathComponent()
            .appendingPathComponent("cancel-\(token.uuidString.lowercased())")
    }

    private func phase(_ job: Job) -> String? {
        guard job.state == "running", let path = job.log,
              let file = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return job.detail }
        defer { try? file.close() }
        guard let end = try? file.seekToEnd() else { return job.detail }
        try? file.seek(toOffset: end > 32768 ? end - 32768 : 0)
        guard let data = try? file.readToEnd(), let text = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"\[\d+/\d+\] ([^\n]+)"#),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range(at: 1), in: text) else { return job.detail }
        let stage = text[range]
        if stage.hasPrefix("Mac shaders") { return "shaders" }
        if stage.hasPrefix("Pipeline archive") { return "pipelines" }
        if stage.hasPrefix("Mac app") { return "packing" }
        return "building"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            if let path = Bundle.main.object(forInfoDictionaryKey: "TonTonUpdateReport") as? String,
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let report = try? JSONDecoder().decode(Report.self, from: data), !report.jobs.isEmpty {
                DisclosureGroup {
                  VStack(alignment: .leading, spacing: 12) {
                    Text(loc.t("tonton.updatesNote")).font(.footnote).foregroundStyle(.secondary)
                    ForEach(report.jobs) { job in
                        HStack(alignment: .top) {
                            Image(systemName: job.state == "installed" ? "checkmark.circle.fill" : job.state == "running" ? "hammer.fill" : "circle")
                                .foregroundStyle(job.state == "installed" ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(job.name)
                                Text(loc.t("tonton.state." + job.state)).font(.caption).foregroundStyle(.secondary)
                                if let detail = phase(job), !detail.isEmpty {
                                    Text(loc.t("tonton.phase." + detail)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let request = cancelRequest(for: job, reportPath: path) {
                                let pending = FileManager.default.fileExists(atPath: request.path)
                                Button(loc.t(pending ? "tonton.cancellingBuild" : "tonton.cancelBuild")) {
                                    do { try Data().write(to: request, options: .atomic) }
                                    catch { cancelError = true }
                                }.disabled(pending)
                            }
                            if let log = job.log, FileManager.default.fileExists(atPath: log) {
                                Button(loc.t("tonton.viewLog")) { NSWorkspace.shared.open(URL(fileURLWithPath: log)) }
                            }
                        }
                    }
                  }
                } label: {
                    Label(loc.t("tonton.updates"), systemImage: "arrow.triangle.2.circlepath").font(.headline)
                }.padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .alert(loc.t("tonton.cancelBuildFailed"), isPresented: $cancelError) {
            Button(loc.t("library.ok"), role: .cancel) {}
        }
    }
}
