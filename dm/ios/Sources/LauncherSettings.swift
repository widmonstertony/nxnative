// Launcher settings, validation and persistence. Shared by the iOS UI, the Mac app's settings window (dm/mac/Launcher.swift) and the native storage regression test.
import Foundation
import Combine

struct Setting: Decodable, Identifiable {
    let env, kind, label, note, def: String
    let section: String?   // heading on the settings screen; absent in older bundles
    let needs: String?     // "<VAR>=<value>": a sub-setting, drawn only while that setting has that value
    let level: String?     // "basic": shown first (the Mac window's Basic settings); any other or none: Advanced settings. The iPhone keeps one list
    let base: Base?        // render scale: the 3D views' size at 1.0, docked and handheld, for the size in pixels (the Mac window)
    struct Base: Decodable { let docked, handheld: [Int] }
    let options: [[String]]?   // choice: [value, label]
    let min, max, step: Double?   // range
    let on, off: String?   // toggle: the values the variable takes (1 / 0 when not given)
    var id: String { env }
    var sectionTitle: String { section ?? "Game" }
    var basic: Bool { level == "basic" }
    var onValue: String { on ?? "1" }
    var offValue: String { off ?? "0" }
    func isDefault(_ v: String) -> Bool {   // a range compares as numbers (a slider writes 1.00 for 1.0)
        kind == "range" ? abs((Double(v) ?? .nan) - (Double(def) ?? .nan)) < 1e-6 : v == def
    }
    func accepts(_ v: String) -> Bool {   // a saved choice the game still offers
        switch kind {
        case "choice": return options?.contains { $0[0] == v } ?? false
        case "range":
            guard !v.contains(where: { $0 == "x" || $0 == "X" }), let n = Double(v), n.isFinite, let lo = min, let hi = max else { return false }   // no hex: launcher.c's check agrees
            return n >= lo && n <= hi
        case "toggle": return v == onValue || v == offValue
        default: return true
        }
    }
    enum CodingKeys: String, CodingKey { case env, kind, label, note, def = "default", section, needs, level, base, options, min, max, step, on, off }
}
struct SettingsFile: Decodable { let settings: [Setting] }

final class LauncherModel: ObservableObject {
    let settings: [Setting]
    let fixed: Set<String>      // set by an env file or by the launch environment: shown, not changed
    let fromLaunch: Set<String>   // of those, the ones the launch environment set (a front end's launch overrides, Xcode; DM_ENV_LAUNCH_KEYS from launcher.c or main.m)
    let ignoreSaved: Bool   // DM_SAVED_CHOICES=0: start from the defaults, and leave the saved choices as they are
    @Published var values: [String: String] = [:]

    private let defaults: UserDefaults

    init(_ settings: [Setting], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = settings
        let env = ProcessInfo.processInfo.environment
        fromLaunch = Set((env["DM_ENV_LAUNCH_KEYS"] ?? "").split(separator: " ").map(String.init))
        fixed = fromLaunch.union((env["DM_ENV_FILE_KEYS"] ?? "").split(separator: " ").map(String.init))
        ignoreSaved = env["DM_SAVED_CHOICES"] == "0"
        if ignoreSaved { fputs("launcher: saved choices ignored (DM_SAVED_CHOICES=0)\n", stderr) }
        for s in settings {
            if fixed.contains(s.env), let v = env[s.env] { values[s.env] = v; continue }
            let saved = ignoreSaved ? nil : defaults.object(forKey: "launcher." + s.env) as? String   // a string, as launcher.c reads it: not string(forKey:), which turns a number into one
            values[s.env] = saved.flatMap { s.accepts($0) ? $0 : nil } ?? s.def   // a saved choice the game no longer offers: its default
        }
    }

    var sections: [String] {
        settings.reduce(into: []) { if !$0.contains($1.sectionTitle) { $0.append($1.sectionTitle) } }
    }
    // A row with "needs" is a sub-setting of the row it names: drawn only while that setting has that value, so a
    // setting that cannot do anything is not offered (an upscaler's detail with the upscaler off, rumble strength
    // with rumble off). A row naming a setting this game does not have stays drawn, as it has nothing to hide behind
    func visible(_ s: Setting) -> Bool {
        guard let n = s.needs, let eq = n.firstIndex(of: "=") else { return true }
        let key = String(n[n.startIndex..<eq]), want = String(n[n.index(after: eq)...])
        guard let v = values[key] else { return true }
        return v == want
    }
    func rows(in section: String) -> [Setting] { settings.filter { $0.sectionTitle == section && visible($0) } }
    // The Mac window: Basic settings first, then Advanced settings, each in the list's sections and order
    func sections(basic: Bool) -> [String] {
        settings.filter { $0.basic == basic }.reduce(into: []) { if !$0.contains($1.sectionTitle) { $0.append($1.sectionTitle) } }
    }
    func rows(in section: String, basic: Bool) -> [Setting] { rows(in: section).filter { $0.basic == basic } }
    // A range's label: its percentage, with the size in pixels for the chosen console mode when the list has the base size (the render scale)
    func rangeLabel(_ s: Setting, _ v: Double) -> String {
        let p = "\(Int((v * 100).rounded())) %"
        guard let b = s.base else { return p }
        let size = (values["DM_OPMODE"] ?? "1") == "0" ? b.handheld : b.docked
        guard size.count == 2 else { return p }
        return "\(Int((Double(size[0]) * v).rounded())) × \(Int((Double(size[1]) * v).rounded())) (\(p))"
    }
    var changed: Bool { settings.contains { !fixed.contains($0.env) && !$0.isDefault(values[$0.env] ?? $0.def) } }

    // Reset every launcher choice to the game's defaults on the screen; values fixed by an env file or at launch stay. The saved choices are forgotten when Play applies
    // the defaults (apply() keeps no default), so Quit after Reset keeps them, and a choice a launch override hides is kept
    func reset() {
        for s in settings where !fixed.contains(s.env) { values[s.env] = s.def }
        fputs("launcher: settings reset to the game's defaults\n", stderr)
    }

    // Before the game starts: every setting not set by an env file goes into the environment (DM_LANG replaces the packed language main.m set as a default). Only a choice that
    // differs from the game's default is stored: a setting the player left at its default follows the defaults of a later build (the settings it was tested with)
    func apply() {
        for s in settings {
            let v = values[s.env] ?? s.def
            if fixed.contains(s.env) { fputs("launcher: \(s.env) kept at \(v) (\(fromLaunch.contains(s.env) ? "launch environment" : "env file"))\n", stderr); continue }
            if !ignoreSaved { if s.isDefault(v) { defaults.removeObject(forKey: "launcher." + s.env) } else { defaults.set(v, forKey: "launcher." + s.env) } }
            setenv(s.env, v, 1); fputs("launcher: \(s.env)=\(v)\(s.isDefault(v) ? "" : " (changed)")\n", stderr)
        }
    }

    // DM_LAUNCHER=0: no screen, but the saved choices still apply (only DM_SAVED_CHOICES=0 ignores them); nothing is written
    func applySaved() {
        for s in settings where !fixed.contains(s.env) {
            let v = values[s.env] ?? s.def
            if !s.isDefault(v) { setenv(s.env, v, 1); fputs("launcher: \(s.env)=\(v) (saved choice)\n", stderr) }
        }
    }
}

// Player-facing translations only: raw setting IDs, option values and saved choices stay unchanged.
// The iPhone/iPad builds use Simplified Chinese even when the system language differs.
enum LauncherText {
    static let simplifiedChinese: [String: String] = [
        "Game": "游戏",
        "Frame generation": "插帧",
        "Off": "关闭",
        "Optical flow (experimental)": "光流插帧（实验性）",
        "Generates one intermediate picture per real frame. Uses image optical flow, not the MetalFX frame interpolator. Real target is at most 60 for 120 Hz output; fast HUD motion may show artifacts.": "每两个真实帧之间生成一张中间画面。此模式使用图像光流，不是 Apple MetalFX 原生插帧；开启时真实目标最高 60 帧，争取 120Hz 显示。快速移动的文字、界面可能变形。",
        "Controls": "操作",
        "Performance": "性能",
        "Version": "版本",
        "Play": "开始游戏",
        "Reset to tested defaults": "恢复已验证的默认设置",
        "Brings back all settings this game was tested with.": "恢复此游戏经过测试的默认设置。",
        "Memory available": "可用内存",
        "Set at launch": "由启动参数设定",
        "Set by an env file": "由配置文件设定",
        "Frame rate": "目标帧率",
        "30 fps": "30 帧/秒",
        "60 fps": "60 帧/秒",
        "120 fps": "120 帧/秒",
        "Experimental engine timing target; actual performance and game speed need device testing.": "实验性帧率目标；实际帧率和游戏速度需要实机测试。",
        "Original 30 fps": "原版 30 帧/秒",
        "Removes the 30 fps limit with variable game timing. Actual frame rate depends on device performance.": "解除 30 帧限制，并按实际经过时间推进游戏。实际帧率取决于设备性能。",
        "Unavailable pending shader fix": "等待着色器修复，暂不可用",
        "This game needs a dual-source shader variant before Metal 4 pipelines can be enabled.": "此游戏的双源混合着色器仍需修复，暂时使用已能运行的标准渲染管线。",
        "Dynamic resolution": "动态分辨率",
        "Adjusts resolution between 70% and 100% under load. Turn off to keep full resolution for the selected console mode.": "根据负载在 70% 至 100% 之间调整分辨率。关闭后使用所选主机模式的完整分辨率。",
        "Render scale": "内部渲染比例",
        "Console mode": "主机模式",
        "Docked": "底座模式",
        "Handheld": "掌机模式",
        "Upscaling": "超分辨率",
        "Standard": "标准缩放（关闭超分）",
        "MetalFX": "MetalFX 超分辨率",
        "Uses more GPU time and can increase heat.": "需要额外 GPU 运算，可能增加发热；是否更流畅取决于内部渲染分辨率和设备性能。",
        "Game language": "游戏语言",
        "Display mode": "显示模式",
        "Window": "窗口",
        "Fullscreen": "全屏",
        "Frame-rate counter": "显示实际帧率",
        "Touch feedback": "触控振动反馈",
        "Game rumble": "游戏振动",
        "Rumble strength": "振动强度",
        "Rumble cutoff": "振动过滤阈值",
        "Frame buffering": "帧缓冲",
        "Up to one frame more display latency.": "可能增加最多一帧的显示延迟。",
        "Metal 4 pipelines": "Metal 4 渲染管线",
        "Keeps a pipeline archive; uses more memory.": "保留渲染管线缓存，会占用更多内存。",
        "Pipeline prebuild": "预编译渲染管线",
        "The first start waits a few minutes for it, once.": "首次启动可能需要等待几分钟，完成后不必重复等待。",
        "Encode thread": "独立渲染编码线程",
        "Hold frames when late": "帧延迟时保持当前画面",
        "Performance HUD": "性能监测面板",
        "American English": "英语（美国）",
        "British English": "英语（英国）",
        "Japanese": "日语",
        "French": "法语",
        "German": "德语",
        "Latin American Spanish": "西班牙语（拉丁美洲）",
        "Spanish": "西班牙语",
        "Italian": "意大利语",
        "Dutch": "荷兰语",
        "Canadian French": "法语（加拿大）",
        "Portuguese": "葡萄牙语",
        "Russian": "俄语",
        "Korean": "韩语",
        "Traditional Chinese": "繁体中文",
        "Simplified Chinese": "简体中文",
        "Brazilian Portuguese": "葡萄牙语（巴西）",
        "Frame interpolation": "插帧",
        "Not available on this device": "此设备暂不支持",
        "Not implemented for this game": "此游戏暂未接入",
    ]
    static func chinese(_ source: String) -> String { simplifiedChinese[source] ?? source }
    static func display(_ source: String) -> String {
#if os(iOS)
        return chinese(source)
#else
        return source
#endif
    }
}
