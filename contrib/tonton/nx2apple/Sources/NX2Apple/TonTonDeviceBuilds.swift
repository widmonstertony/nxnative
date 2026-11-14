import AppKit
import SwiftUI
import NXCore
import NXModel
import NXLauncher

/// Device jobs are separate from the native new-build queue below this card.
struct TonTonDeviceBuilds: View {
    var body: some View {
        let defaultConfig = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TonTon Gamebox/device-builds.json").path
        let configuredScript = Bundle.main.object(forInfoDictionaryKey: "TonTonDeviceBuildController") as? String
        let python = Bundle.main.object(forInfoDictionaryKey: "TonTonDeviceBuildPython") as? String ?? "/usr/bin/python3"
        if let config = Bundle.main.object(forInfoDictionaryKey: "TonTonDeviceBuildConfig") as? String ?? defaultConfig,
           FileManager.default.fileExists(atPath: config),
           let script = configuredScript ??
               Bundle.main.url(forResource: "tonton_device_builds", withExtension: "py", subdirectory: "tools")?.path {
            // Python doesn't need access to the directory containing the app or its build venv.
            // Load the signed bundled controller ourselves, while honoring explicit local overrides.
            let bundledSource = configuredScript == nil ? try? String(contentsOfFile: script, encoding: .utf8) : nil
            DeviceBuildCard(python: python, script: script, config: config, bundledSource: bundledSource)
        }
    }
}

private struct DeviceBuildCard: View {
    @StateObject private var store: DeviceBuildStore
    @EnvironmentObject var loc: Localizer
    @State private var showingLog = false
    @State private var selectedName = ""

    init(python: String, script: String, config: String, bundledSource: String?) {
        _store = StateObject(wrappedValue: DeviceBuildStore(python: python, script: script, config: config, bundledSource: bundledSource))
    }

    var body: some View {
        CardGroup(loc.t("deviceBuild.title")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(loc.t("deviceBuild.note")).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(loc.t("deviceBuild.refresh")) { store.refresh() }.disabled(store.busy)
                }
                if !store.error.isEmpty { Text(store.error).foregroundStyle(.red).textSelection(.enabled) }
                if store.jobs.isEmpty && store.error.isEmpty { Text(loc.t("deviceBuild.loading")).foregroundStyle(.secondary) }
                ForEach(store.jobs) { job in
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(job.name).font(.headline)
                            Text(job.devices.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(loc.t("deviceBuild.state." + job.state))
                                .foregroundStyle(job.state == "running" ? Color.accentColor : job.state == "needs_attention" ? .red : .secondary)
                        }
                        if job.total > 0 {
                            ProgressView(value: job.fraction)
                            Text("\(job.completed.formatted()) / \(job.total.formatted()) · \(Int(job.fraction * 100))%")
                                .monospacedDigit().font(.caption)
                        }
                        Text(detail(job)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack {
                            Button(loc.t("deviceBuild.resume")) { store.resume(job) }.disabled(store.busy || !job.canResume)
                            Button(loc.t("deviceBuild.pause")) { store.pause(job) }.disabled(store.busy || !job.canPause)
                            Button(loc.t("deviceBuild.log")) {
                                selectedName = job.name
                                Task { await store.showLog(job)?.value; showingLog = true }
                            }.disabled(store.busy)
                            Button(loc.t("deviceBuild.folder")) { NSWorkspace.shared.open(URL(fileURLWithPath: job.folder)) }
                            Spacer()
                        }.buttonStyle(LauncherSecondaryButtonStyle())
                    }.accessibilityElement(children: .contain)
                }
            }.padding(18)
        }
        .task {
            while !Task.isCancelled {
                await store.refresh()?.value
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { break }
            }
        }
        .sheet(isPresented: $showingLog) {
            VStack(alignment: .leading, spacing: 12) {
                Text(selectedName).font(.headline)
                ScrollView {
                    Text(store.logText).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(loc.t("deviceBuild.close")) { showingLog = false }.keyboardShortcut(.cancelAction)
            }.padding(20).frame(width: 850, height: 550)
        }
    }

    private func detail(_ job: DeviceBuildJob) -> String {
        if job.state == "waiting_space", let free = job.freeBytes, let reserve = job.reserveBytes {
            return String(format: loc.t("deviceBuild.space"),
                          ByteCountFormatter.string(fromByteCount: free, countStyle: .binary),
                          ByteCountFormatter.string(fromByteCount: reserve, countStyle: .binary))
        }
        let key = "deviceBuild.detail." + job.detail
        let value = loc.t(key)
        return value == key ? job.detail : value
    }
}
